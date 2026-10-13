import {spawnSync} from "node:child_process";
import {createHash, randomUUID} from "node:crypto";
import {lstatSync} from "node:fs";
import {cp, mkdir, mkdtemp, readFile, rm, stat, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {basename, dirname, relative, resolve, sep} from "node:path";
import {McpServer} from "@modelcontextprotocol/sdk/server/mcp.js";
import {StdioServerTransport} from "@modelcontextprotocol/sdk/server/stdio.js";
import {z} from "zod";
import {fileURLToPath} from "node:url";
import {authorityContract, validateDeclarativeContract} from "./contract.ts";

const serverRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const repoRoot = resolve(process.env.NIX_CONFIG_MCP_ROOT ?? serverRoot);
const deniedNames = new Set([".env", ".env.local", ".env.production", "id_rsa", "id_ed25519"]);
// This public template is allowed only through an explicitly reviewed
// whole-tree commit; all other .env* paths stay protected.
const reviewedPublicEnvExamplePath = "vps/web-research/.env.example";
// `secrets` is denied by all tools except the reviewed whole-tree commit path,
// which may include secret changes (e.g. SOPS ciphertext) under explicit review.
const deniedDirectories = new Set([".git", "node_modules"]);
const operations = new Map<string, Operation>();
const workingTreeOperations = new Map<string, WorkingTreeOperation>();
const maxFileBytes = 512 * 1024;
const maxOperationPaths = 128;
const maxOperationBytes = 8 * 1024 * 1024;
const maxStoredOperations = 16;
const fileListLimit = 500;
const operationTtlMs = 30 * 60 * 1000;

type Change = {
  path: string;
  beforeHash: string | null;
  before: string | null;
  afterHash: string | null;
  after: string | null;
};

type Operation = {
  id: string;
  hash: string;
  kind: string;
  createdAt: string;
  changes: Change[];
};

type WorkingTreeSnapshot = {
  paths: string[];
  diff: string;
  contentHashes: Array<{path: string; hash: string | null}>;
};

type WorkingTreeOperation = {
  id: string;
  hash: string;
  kind: "working-tree-commit";
  createdAt: string;
  snapshot: WorkingTreeSnapshot;
};

const changeSchema = z.object({
  path: z.string().min(1).describe("Repository-relative path. Denied: secrets/, .env*, .git/, private keys and certificates, symlinks, and names beginning with ':'."),
  content: z.string().nullable().describe("Complete new file content. null deletes the file; an empty string truncates it to zero bytes."),
});

// MCP ToolAnnotations, expressed once instead of per registration. The three
// groups mirror the Authority column in mcp/README.md: read-only inspection,
// prepare-only (mints an approval token, writes nothing), and the mutation that
// the token gates. openWorldHint marks tools that may reach the network through
// locked flake inputs.
const inspectLocal = {readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false};
const inspectNetworked = {readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true};
const prepareLocal = {readOnlyHint: true, destructiveHint: false, idempotentHint: false, openWorldHint: false};
const prepareNetworked = {readOnlyHint: true, destructiveHint: false, idempotentHint: false, openWorldHint: true};
const modifyAdditive = {readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false};
const modifyDestructive = {readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false};

function pruneOperationStore<T extends {createdAt: string}>(store: Map<string, T>, now = Date.now()) {
  const cutoff = now - operationTtlMs;
  for (const [id, operation] of store) {
    const createdAt = Date.parse(operation.createdAt);
    if (!Number.isFinite(createdAt) || createdAt < cutoff) store.delete(id);
  }
}

function storeOperation<T extends {id: string; createdAt: string}>(store: Map<string, T>, operation: T) {
  pruneOperationStore(store);
  while (store.size >= maxStoredOperations) {
    const oldest = store.keys().next().value;
    if (oldest === undefined) break;
    store.delete(oldest);
  }
  store.set(operation.id, operation);
}

function storedChangeBytes(change: Pick<Change, "before" | "after">) {
  return Buffer.byteLength(change.before ?? "", "utf8") + Buffer.byteLength(change.after ?? "", "utf8");
}

function assertOperationBudget(changes: Change[]) {
  if (changes.length > maxOperationPaths) fail(`An operation may contain at most ${maxOperationPaths} paths.`);
  const bytes = changes.reduce((total, change) => total + storedChangeBytes(change), 0);
  if (bytes > maxOperationBytes) fail(`An operation may retain at most ${maxOperationBytes} bytes of file content.`);
}

function text(value: unknown) {
  return typeof value === "string" ? value : JSON.stringify(value, null, 2);
}

function result(value: unknown) {
  return {content: [{type: "text" as const, text: text(value)}]};
}

function fail(message: string): never {
  throw new Error(message);
}

function safeRelativePath(input: string, allowSecrets = false): string {
  if (input.includes("\0")) fail("Paths cannot contain NUL bytes.");
  const normalized = input.replaceAll("\\", "/");
  const absolute = resolve(repoRoot, normalized);
  const rel = relative(repoRoot, absolute);
  if (rel === "" || rel === ".." || rel.startsWith(`..${sep}`) || rel.includes(`${sep}.git${sep}`)) {
    fail("The path must stay inside the repository.");
  }
  if (rel.startsWith(":")) {
    fail("Filenames beginning with ':' are denied because Git treats them as pathspec magic.");
  }
  const parts = rel.split(sep);
  const isReviewedPublicEnvExample =
    allowSecrets && rel === reviewedPublicEnvExamplePath;
  if (parts.some((part) => deniedNames.has(part) || part.startsWith(".env")) && !isReviewedPublicEnvExample) {
    fail("This path is denied by the project MCP security policy.");
  }
  if (parts.some((part) => deniedDirectories.has(part) || (part === "secrets" && !allowSecrets))) {
    fail("This path is denied by the project MCP security policy.");
  }
  if (parts.some((part) => /\.(pem|key|p12|pfx|asc)$/i.test(part))) {
    fail("Private-key and certificate paths are denied by the project MCP security policy.");
  }
  return rel.split(sep).join("/");
}

async function safePath(input: string, mustExist = false, allowSecrets = false): Promise<{relative: string; absolute: string}> {
  const relativePath = safeRelativePath(input, allowSecrets);
  const absolute = resolve(repoRoot, relativePath);
  let current = repoRoot;
  for (const part of relativePath.split("/")) {
    current = resolve(current, part);
    try {
      if (lstatSync(current).isSymbolicLink()) fail("Symbolic-link paths are denied to prevent repository escapes.");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") break;
      throw error;
    }
  }
  try {
    await stat(absolute);
    if (lstatSync(absolute).isSymbolicLink()) fail("Symbolic-link paths are denied to prevent repository escapes.");
  } catch (error) {
    if (mustExist || (error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  return {relative: relativePath, absolute};
}

function digest(value: string | null): string | null {
  return value === null ? null : createHash("sha256").update(value).digest("hex");
}

async function readSafeFile(path: string, allowSecrets = false): Promise<string | null> {
  const target = await safePath(path, false, allowSecrets);
  try {
    const info = await stat(target.absolute);
    if (!info.isFile() || info.size > maxFileBytes) fail("The file is not a regular file or is too large.");
    return await readFile(target.absolute, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}

async function snapshotChanges(workspace: string, paths: string[]): Promise<Change[]> {
  const changes: Change[] = [];
  for (const path of paths) {
    const relativePath = safeRelativePath(path);
    const before = await readSafeFile(relativePath);
    let after: string | null = null;
    try {
      const target = resolve(workspace, relativePath);
      const info = await stat(target);
      if (info.isSymbolicLink() || !info.isFile() || info.size > maxFileBytes) fail(`Invalid generated file: ${relativePath}`);
      after = await readFile(target, "utf8");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    if (before !== after) {
      const change = {path: relativePath, beforeHash: digest(before), before, afterHash: digest(after), after};
      assertOperationBudget([...changes, change]);
      changes.push(change);
    }
  }
  return changes;
}

async function createWorkspace(): Promise<string> {
  const workspace = await mkdtemp(`${tmpdir()}/nix-config-mcp-`);
  await cp(`${repoRoot}/.`, workspace, {
    recursive: true,
    filter: (source) => {
      const relativePath = relative(repoRoot, source);
      if (!relativePath) return true;
      if (lstatSync(source).isSymbolicLink()) return false;
      try {
        safeRelativePath(relativePath);
        return true;
      } catch {
        return false;
      }
    },
  });
  const initialized = runAllowed("git", ["init", "--quiet"], workspace);
  if (initialized.status !== 0) {
    await rm(workspace, {recursive: true, force: true});
    fail(`Could not initialize temporary workspace: ${initialized.stderr}`);
  }
  const indexed = runAllowed("git", ["add", "--all"], workspace);
  if (indexed.status !== 0) {
    await rm(workspace, {recursive: true, force: true});
    fail(`Could not index temporary workspace: ${indexed.stderr}`);
  }
  return workspace;
}

// Screened as substrings over every argv element of every spawned command, so
// these also constrain user-supplied text: commit messages, paths, and search
// patterns. Declared in the affected tool schemas and named in the error below.
const screenedArgvTokens = [";", "sudo", "nixos-rebuild"];

function screenedToken(value: string): string | undefined {
  return screenedArgvTokens.find((token) => value.includes(token));
}

function runAllowed(command: string, args: string[], cwd: string, timeout = 120_000) {
  const allowed = new Set(["nix", "git", "rg"]);
  if (!allowed.has(command)) fail(`Command is not allowed: ${command}`);
  const screened = args.find((arg) => screenedToken(arg) !== undefined);
  if (screened !== undefined) {
    const token = screenedToken(screened);
    const shown = screened.length > 60 ? `${screened.slice(0, 57)}...` : screened;
    fail(`The requested command contains a prohibited operation: "${token}" appears in ${JSON.stringify(shown)}. Every argument is screened as a substring, so commit subjects, paths, and search patterns are screened too; write a comma where a semicolon was meant.`);
  }
  const completed = spawnSync(command, args, {cwd, encoding: "utf8", timeout, maxBuffer: 4 * 1024 * 1024});
  return {
    kind: "command",
    command: [command, ...args].join(" "),
    status: completed.status,
    signal: completed.signal,
    stdout: completed.stdout ?? "",
    stderr: completed.stderr ?? "",
    timedOut: (completed.error as NodeJS.ErrnoException | undefined)?.code === "ETIMEDOUT",
  };
}

function runFixed(command: string, args: string[], cwd = repoRoot, timeout = 120_000) {
  const completed = spawnSync(command, args, {cwd, encoding: "utf8", timeout, maxBuffer: 4 * 1024 * 1024});
  return {
    kind: "command",
    command: [command, ...args].join(" "),
    status: completed.status,
    signal: completed.signal,
    stdout: completed.stdout ?? "",
    stderr: completed.stderr ?? "",
    timedOut: (completed.error as NodeJS.ErrnoException | undefined)?.code === "ETIMEDOUT",
  };
}

type DocumentationFinding = {
  kind: "missing-path" | "stale-reference" | "mcp-documentation";
  path: string;
  line?: number;
  message: string;
  evidence?: string;
};

async function auditDocumentation() {
  const listed = runAllowed("git", ["ls-files", "--cached", "--others", "--exclude-standard"], repoRoot);
  if (listed.status !== 0) return {kind: "documentation-audit", valid: false, filesScanned: 0, findings: [{kind: "stale-reference", path: "", message: listed.stderr || "Could not list repository files."}]};

  const markdownPaths = visibleGitLines(listed.stdout)
    .filter((path) => path.endsWith(".md") && path !== "AGENTS.md" && !path.startsWith(".codex/") && !path.startsWith("secrets/"));
  const findings: DocumentationFinding[] = [];
  const staleReferences = [
    {pattern: /ACL reconciliation|home-acl-reconcile|services\.homeAcl/i, message: "Documentation references removed ACL reconciliation wiring."},
    {pattern: /scripts\/.*audit|`scripts\/`.*audit/i, message: "Documentation references removed audit tooling."},
  ];

  for (const path of markdownPaths) {
    const content = await readSafeFile(path);
    if (content === null) continue;
    const lines = content.split("\n");
    lines.forEach((line, index) => {
      for (const stale of staleReferences) {
        if (stale.pattern.test(line)) findings.push({kind: "stale-reference", path, line: index + 1, message: stale.message, evidence: line.trim()});
      }
      for (const match of line.matchAll(/`([^`]+)`/g)) {
        const candidate = match[1].replace(/[),.;:]$/, "");
        if (!candidate.includes("/") || /\s|[:+*()<>"'=]/.test(candidate) || candidate.includes("://") || candidate.includes("$") || candidate.startsWith("/") || candidate.startsWith("~")) continue;
        const candidates = [candidate];
        if (path.startsWith("modules/") && !candidate.startsWith("modules/")) candidates.push(`modules/nixos/${candidate}`);
        const exists = candidates.some((value) => {
          try {
            const relativePath = safeRelativePath(value);
            lstatSync(resolve(repoRoot, relativePath));
            return true;
          } catch {
            return false;
          }
        });
        if (!exists) findings.push({kind: "missing-path", path, line: index + 1, message: `Documented repository path does not exist: ${candidate}`, evidence: line.trim()});
      }
    });
  }

  const serverSource = await readSafeFile("mcp/src/server.ts") ?? "";
  const mcpReadme = await readSafeFile("mcp/README.md") ?? "";
  for (const match of serverSource.matchAll(/server\.tool\("([^"]+)"/g)) {
    const name = match[1];
    if (!mcpReadme.includes(`\`${name}\``)) findings.push({kind: "mcp-documentation", path: "mcp/README.md", message: `MCP tool is not documented: ${name}`});
  }

  return {kind: "documentation-audit", valid: findings.length === 0, filesScanned: markdownPaths.length, findings};
}

function operationHash(kind: string, changes: Change[]): string {
  return createHash("sha256").update(JSON.stringify({kind, changes}, null, 2)).digest("hex");
}

function operationSummary(operation: Operation) {
  return {
    operationId: operation.id,
    approvalHash: operation.hash,
    kind: operation.kind,
    createdAt: operation.createdAt,
    changes: operation.changes.map(({path, beforeHash, afterHash, before, after}) => ({
      path,
      beforeHash,
      afterHash,
      action: before === null ? "create" : after === null ? "delete" : "update",
    })),
  };
}

function unifiedDiff(change: Change): string {
  const before = change.before ?? "";
  const after = change.after ?? "";
  const splitLines = (value: string) => {
    if (value.length === 0) return [];
    const lines = value.split("\n");
    if (lines.at(-1) === "") lines.pop();
    return lines;
  };
  const oldLines = splitLines(before);
  const newLines = splitLines(after);
  const output = [`--- a/${change.path}`, `+++ b/${change.path}`, `@@ -1,${oldLines.length} +1,${newLines.length} @@`];
  output.push(...oldLines.map((line) => `-${line}`), ...newLines.map((line) => `+${line}`));
  return output.join("\n");
}

function visibleGitLines(output: string): string[] {
  return output.split("\n").filter((line) => {
    const path = line.slice(3).split(" -> ").at(-1)?.trim();
    if (!path) return true;
    try {
      safeRelativePath(path);
      return true;
    } catch {
      return false;
    }
  });
}

function workingTreeRecords(statusOutput: string, allowSecrets = false): Array<{path: string; index: string; worktree: string}> {
  return statusOutput.split("\0").filter(Boolean).flatMap((record) => {
    if (record.length < 4) return [];
    return [{index: record[0], worktree: record[1], path: safeRelativePath(record.slice(3), allowSecrets)}];
  });
}

function workingTreePaths(statusOutput: string, allowSecrets = false): string[] {
  return [...new Set(workingTreeRecords(statusOutput, allowSecrets).map((record) => record.path))].sort();
}

async function workingTreeDiff(paths: string[]): Promise<string> {
  const othersList = runAllowed("git", ["ls-files", "--others", "--exclude-standard", "--", ...paths], repoRoot);
  const untracked = new Set(othersList.stdout.split("\n").map((line) => line.trim()).filter(Boolean));

  const tracked: string[] = [];
  for (const path of paths) {
    if (!untracked.has(path)) tracked.push(path);
  }

  const diffs: string[] = [];
  let diffBytes = 0;
  if (tracked.length > 0) {
    const trackedDiff = runAllowed("git", ["diff", "--no-ext-diff", "--binary", "--full-index", "HEAD", "--", ...tracked], repoRoot);
    if (trackedDiff.status !== 0) fail(trackedDiff.stderr || "Could not create the working-tree diff.");
    if (trackedDiff.stdout) {
      diffBytes += Buffer.byteLength(trackedDiff.stdout, "utf8");
      if (diffBytes > maxOperationBytes) fail(`The working-tree diff exceeds the ${maxOperationBytes}-byte operation budget.`);
      diffs.push(trackedDiff.stdout);
    }
  }
  for (const path of untracked) {
    const target = await safePath(path, false, true);
    const untrackedDiff = runAllowed("git", ["diff", "--no-index", "--binary", "--", "/dev/null", target.absolute], repoRoot);
    if (untrackedDiff.status !== 0 && untrackedDiff.status !== 1) fail(untrackedDiff.stderr || `Could not diff ${path}.`);
    if (untrackedDiff.stdout) {
      diffBytes += Buffer.byteLength(untrackedDiff.stdout, "utf8");
      if (diffBytes > maxOperationBytes) fail(`The working-tree diff exceeds the ${maxOperationBytes}-byte operation budget.`);
      diffs.push(untrackedDiff.stdout);
    }
  }
  return diffs.join("\n");
}

async function captureWorkingTreeSnapshot(): Promise<WorkingTreeSnapshot> {
  const status = runAllowed("git", ["status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all"], repoRoot);
  if (status.status !== 0) fail(status.stderr || "Could not inspect the working tree.");
  const paths = workingTreePaths(status.stdout, true);
  if (paths.length > maxOperationPaths) fail(`The working-tree operation may contain at most ${maxOperationPaths} paths.`);
  const contentHashes = await Promise.all(paths.map(async (path) => {
    await safePath(path, false, true);
    return {path, hash: digest(await readSafeFile(path, true))};
  }));
  return {paths, diff: await workingTreeDiff(paths), contentHashes};
}

function workingTreeOperationHash(snapshot: WorkingTreeSnapshot): string {
  return createHash("sha256").update(JSON.stringify(snapshot, null, 2)).digest("hex");
}

function workingTreeOperationSummary(operation: WorkingTreeOperation) {
  return {
    operationId: operation.id,
    approvalHash: operation.hash,
    kind: operation.kind,
    createdAt: operation.createdAt,
    paths: operation.snapshot.paths,
    diff: operation.snapshot.diff,
  };
}

async function createWorkingTreeOperation(): Promise<WorkingTreeOperation> {
  const snapshot = await captureWorkingTreeSnapshot();
  if (snapshot.paths.length === 0) fail("The working tree is clean; there is nothing to prepare.");
  const operation: WorkingTreeOperation = {
    id: randomUUID(),
    hash: workingTreeOperationHash(snapshot),
    kind: "working-tree-commit",
    createdAt: new Date().toISOString(),
    snapshot,
  };
  storeOperation(workingTreeOperations, operation);
  return operation;
}

function getWorkingTreeOperation(id: string, approvalHash: string): WorkingTreeOperation {
  pruneOperationStore(workingTreeOperations);
  const operation = workingTreeOperations.get(id);
  if (!operation || operation.hash !== approvalHash) {
    fail(`The working-tree operation ID or approval hash is invalid, expired, or evicted. Operations expire ${operationTtlMs / 60_000} minutes after preparation and the server retains at most ${maxStoredOperations}; run prepare_working_tree_commit again.`);
  }
  return operation;
}

async function ensureWorkingTreeOperationCurrent(operation: WorkingTreeOperation) {
  const current = await captureWorkingTreeSnapshot();
  if (workingTreeOperationHash(current) !== operation.hash) fail("The working tree changed after preparation; prepare a new review operation.");
}

// Commit paths and messages become git argv only inside the staging loop, so the
// spawn guard would otherwise reject them after earlier files were already
// committed. Screen up front: identical acceptance, but no partial batch.
function assertScreenedCommitArguments(commits: Array<{path: string; message: string}>) {
  for (const entry of commits) {
    for (const value of [entry.path, entry.message]) {
      const token = screenedToken(value);
      if (token !== undefined) {
        const shown = value.length > 60 ? `${value.slice(0, 57)}...` : value;
        fail(`Commit arguments are screened before any staging: "${token}" appears in ${JSON.stringify(shown)}. Nothing was staged and no commit was made.`);
      }
    }
  }
}

function validCommitMessage(message: string) {
  const [subject, ...trailers] = message.split("\n");
  return subject.endsWith(".") && trailers.every((line) => /^Co-authored-by:\s+.+\s+<[^<>\s@]+@[^<>\s@]+>$/.test(line));
}

function createOperation(kind: string, changes: Change[]): Operation {
  if (changes.length === 0) fail("The proposed operation produces no changes.");
  assertOperationBudget(changes);
  const operation: Operation = {
    id: randomUUID(),
    hash: operationHash(kind, changes),
    kind,
    createdAt: new Date().toISOString(),
    changes,
  };
  storeOperation(operations, operation);
  return operation;
}

async function ensureOperationCurrent(operation: Operation) {
  for (const change of operation.changes) {
    const current = await readSafeFile(change.path);
    if (digest(current) !== change.beforeHash) fail(`The file changed after preparation: ${change.path}`);
  }
}

function getOperation(id: string, approvalHash: string): Operation {
  pruneOperationStore(operations);
  const operation = operations.get(id);
  if (!operation || operation.hash !== approvalHash) {
    fail(`The operation ID or approval hash is invalid, expired, or evicted. Operations expire ${operationTtlMs / 60_000} minutes after preparation and the server retains at most ${maxStoredOperations} per family, oldest first; run the matching prepare tool again.`);
  }
  return operation;
}

const server = new McpServer({name: "nix-config-project-mcp", version: "0.1.0"});

server.tool("read_project_overview", "List non-sensitive repository files and the primary NixOS entry points without modifying the checkout.", {}, {title: "Read project overview", ...inspectLocal}, async () => {
  const output = runAllowed("git", ["ls-files", "--cached", "--others", "--exclude-standard"], repoRoot);
  const visible = visibleGitLines(output.stdout).filter(Boolean);
  return result({
    kind: "project-overview",
    repository: repoRoot,
    files: visible.slice(0, fileListLimit),
    fileCount: visible.length,
    truncated: visible.length > fileListLimit,
    fileListLimit,
    flake: "flake.nix",
    host: "hosts/hiraeth/default.nix",
    fixedIdentifierNote: "flake and host are constants declared by this server, not discovered paths.",
  });
});

server.tool("read_authority_contract", "Explain the MCP repository boundary, approval model, declarative rules, and protected paths.", {}, {title: "Read authority contract", ...inspectLocal}, async () => {
  return result({kind: "authority-contract", repository: repoRoot, ...authorityContract});
});

server.tool("validate_declarative_contract", "Validate declarative and MCP authority conventions from repository source only.", {}, {title: "Validate declarative contract", ...inspectLocal}, async () => {
  const paths = [
    "mcp/src/server.ts",
  ];
  const entries = await Promise.all(paths.map(async (path) => [path, (await readSafeFile(path)) ?? ""] as const));
  return result({kind: "declarative-contract", repository: repoRoot, ...validateDeclarativeContract(Object.fromEntries(entries))});
});

server.tool("read_project_file", "Read one non-sensitive regular file inside the repository.", {path: z.string().describe("Repository-relative path to one regular file. A missing file is an error, not an empty result. The denied path classes and the 512 KiB read cap apply.")}, {title: "Read one project file", ...inspectLocal}, async ({path}) => {
  const content = await readSafeFile(path);
  if (content === null) fail("The file does not exist.");
  return result({kind: "file-content", path: safeRelativePath(path), content});
});

server.tool("find_nix_references", "Find text references in Nix files without running arbitrary shell commands. Results silently exclude secrets/** and are limited to *.nix files.", {query: z.string().min(1).describe("ripgrep regular expression, not a literal phrase."), path: z.string().default(".").describe("Repository-relative file or directory to search; defaults to the repository root.")}, {title: "Find references in Nix files", ...inspectLocal}, async ({query, path}) => {
  const target = safeRelativePath(path);
  return result(runAllowed("rg", ["--line-number", "--glob", "*.nix", "--glob", "!secrets/**", "--", query, target], repoRoot));
});

server.tool("get_git_status", "Return the current branch and complete non-sensitive working-tree status.", {}, {title: "Get Git status", ...inspectLocal}, async () => {
  const status = runAllowed("git", ["status", "--short", "--branch", "--untracked-files=all"], repoRoot);
  return result({...status, stdout: visibleGitLines(status.stdout).join("\n")});
});

server.tool("inspect_flake", "Inspect flake outputs using the read-only nix flake show command.", {}, {title: "Inspect flake outputs", ...inspectNetworked}, async () => {
  return result(runAllowed("nix", ["flake", "show", "--json", "."], repoRoot, 120_000));
});

server.tool("audit_documentation", "Audit tracked Markdown documentation for stale legacy claims, missing repository paths, and undocumented MCP tools without modifying the checkout. Findings carry kind 'missing-path', 'stale-reference', or 'mcp-documentation', and valid is false whenever any finding is present.", {}, {title: "Audit documentation", ...inspectLocal}, async () => {
  return result(await auditDocumentation());
});

server.tool("validate_mcp", "Run the fixed repository MCP test suite without accepting command arguments or modifying the checkout.", {}, {title: "Run the MCP test suite", ...inspectLocal}, async () => {
  return result(runFixed("bun", ["test", "mcp"], repoRoot, 300_000));
});

server.tool("validate_repository", "Run the bounded documentation audit, MCP test suite, and read-only Nix flake check as separate results.", {}, {title: "Validate the repository", ...inspectNetworked}, async () => {
  return result({
    kind: "repository-validation",
    documentation: await auditDocumentation(),
    mcp: runFixed("bun", ["test", "mcp"], repoRoot, 300_000),
    flake: runAllowed("nix", ["flake", "check", "--no-build", "--show-trace"], repoRoot, 300_000),
  });
});

server.tool("prepare_working_tree_commit", "Prepare the complete visible dirty working tree for review; returns a diff and approval hash without modifying the checkout. Unlike every other tool, this snapshot may include secrets/** and the public template vps/web-research/.env.example, and it fails as a whole if any dirty path is a symlink, a private key, or a ':'-prefixed Git pathspec name.", {}, {title: "Prepare a working-tree commit", ...prepareLocal}, async () => {
  return result(workingTreeOperationSummary(await createWorkingTreeOperation()));
});

server.tool("git_commit_working_tree", "Commit the reviewed working tree one file per commit after rechecking the exact approved snapshot. Requires prepare_working_tree_commit and no apply step. Each file requires its own message; all reviewed paths must be represented, and no other path may be committed. Subjects end with a period.", {
  operationId: z.string().describe("Operation ID from prepare_working_tree_commit. No apply step is involved."),
  approvalHash: z.string().describe("Approval hash returned with that operation ID; rechecked against the snapshot before staging."),
  commits: z.array(z.object({
    path: z.string().min(1).describe("One reviewed path from the prepare result. Every reviewed path must appear exactly once; missing, extra, or duplicated paths are rejected."),
    message: z.string().min(1).max(4096).describe("Commit subject ending with a period. Any further line must be a valid 'Co-authored-by: Name <email>' trailer. Screened as argv, so avoid a semicolon anywhere in the message."),
  })).min(1),
}, {title: "Commit the reviewed working tree", ...modifyAdditive}, async ({operationId, approvalHash, commits}) => {
  const operation = getWorkingTreeOperation(operationId, approvalHash);
  for (const entry of commits) {
    if (!validCommitMessage(entry.message)) fail("Commit messages must have a sentence-style subject ending with a period; optional lines may be valid Co-authored-by trailers.");
  }
  const requestedPaths = commits.map((entry) => safeRelativePath(entry.path, true));
  const reviewed = new Set(operation.snapshot.paths);
  if (requestedPaths.length !== reviewed.size) fail(`Provide exactly one commit per reviewed file (${reviewed.size} expected, ${requestedPaths.length} given).`);
  for (const path of requestedPaths) {
    if (!reviewed.has(path)) fail(`The path was not part of the reviewed snapshot: ${path}`);
  }
  if (new Set(requestedPaths).size !== requestedPaths.length) fail("Each reviewed file may appear only once.");
  assertScreenedCommitArguments(commits);

  await ensureWorkingTreeOperationCurrent(operation);
  const beforeStatus = runAllowed("git", ["status", "--short", "--untracked-files=all"], repoRoot);
  if (beforeStatus.status !== 0) fail(beforeStatus.stderr || "Could not inspect the working tree before committing.");
  const status = runAllowed("git", ["status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all"], repoRoot);
  if (status.status !== 0) fail(status.stderr || "Could not inspect the working tree before committing.");
  const statusByPath = new Map(workingTreeRecords(status.stdout, true).map((record) => [record.path, record]));

  const results = [];
  for (const entry of commits) {
    const path = safeRelativePath(entry.path, true);
    const current = await readSafeFile(path, true);
    const recorded = operation.snapshot.contentHashes.find((record) => record.path === path);
    if (!recorded) fail(`The file was not part of the reviewed snapshot: ${path}`);
    if (digest(current) !== recorded.hash) fail(`The file changed after preparation: ${path}`);
    if (current !== null || statusByPath.get(path)?.worktree !== " ") {
      // Stage the exact path, including an unstaged deletion.
      const staged = runAllowed("git", ["add", "--all", "--", path], repoRoot);
      if (staged.status !== 0) fail(staged.stderr || `Could not stage the reviewed file: ${path}`);
    }
    const commit = runAllowed("git", ["commit", "-m", entry.message, "--", path], repoRoot, 120_000);
    results.push({path, ...commit});
    if (commit.status !== 0) break;
  }

  const afterStatus = runAllowed("git", ["status", "--short", "--untracked-files=all"], repoRoot);
  const ok = results.length === requestedPaths.length && results.every((commit) => commit.status === 0);
  const partial = results.some((commit) => commit.status === 0) && results.length < requestedPaths.length;
  if (ok) workingTreeOperations.delete(operationId);
  return result({
    ok,
    partial,
    operationId,
    approvalHash,
    fileCount: requestedPaths.length,
    beforeStatus: {...beforeStatus, stdout: visibleGitLines(beforeStatus.stdout).join("\n")},
    commits: results,
    afterStatus: {...afterStatus, stdout: visibleGitLines(afterStatus.stdout).join("\n")},
  });
});

server.tool("prepare_patch", "Prepare exact file contents against the current checkout without modifying it; the returned operation requires approval before application with apply_approved_patch. Set content to null to delete a file.", {changes: z.array(changeSchema).min(1)}, {title: "Prepare a file patch", ...prepareLocal}, async ({changes}) => {
  if (changes.length > maxOperationPaths) fail(`A patch may contain at most ${maxOperationPaths} paths.`);
  const preparedChanges: Change[] = [];
  const seen = new Set<string>();
  for (const change of changes) {
    const path = safeRelativePath(change.path);
    if (seen.has(path)) fail(`A path may appear only once in a patch: ${path}`);
    seen.add(path);
    if (change.content !== null && Buffer.byteLength(change.content, "utf8") > maxFileBytes) fail(`The proposed file is too large: ${path}`);
    const before = await readSafeFile(path);
    if (change.content === null && before === null) fail(`Cannot delete a file that does not exist: ${path}`);
    preparedChanges.push({path, beforeHash: digest(before), before, afterHash: digest(change.content), after: change.content});
    assertOperationBudget(preparedChanges);
  }
  if (preparedChanges.some((change) => change.beforeHash === change.afterHash)) fail("The proposed patch contains no-op changes.");
  const operation = createOperation("patch", preparedChanges);
  return result({...operationSummary(operation), diff: operation.changes.map(unifiedDiff).join("\n")});
});

server.tool("prepare_format", "Run the flake formatter in a temporary isolated workspace and return a reviewable patch without modifying the checkout.", {paths: z.array(z.string()).default([]).describe("Nix files to format. An empty list formats every tracked and untracked .nix file. Reports only a message when formatting changes nothing.")}, {title: "Prepare a formatter patch", ...prepareNetworked}, async ({paths}) => {
  const workspace = await createWorkspace();
  try {
    const formatted = runAllowed("nix", ["fmt", "."], workspace, 120_000);
    if (formatted.status !== 0) return result(formatted);
    const allPaths = runAllowed("git", ["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.nix"], repoRoot).stdout.split("\n").filter(Boolean);
    const selected = paths.length ? paths.map((path) => safeRelativePath(path)) : allPaths;
    const changes = await snapshotChanges(workspace, selected);
    if (changes.length === 0) return result({kind: "no-op", message: "Formatting produced no changes.", command: formatted.command});
    const operation = createOperation("format", changes);
    return result({...operationSummary(operation), diff: changes.map(unifiedDiff).join("\n"), command: formatted.command});
  } finally {
    await rm(workspace, {recursive: true, force: true});
  }
});

server.tool("prepare_flake_lock_update", "Update flake.lock in a temporary isolated workspace and return only that file's reviewable patch.", {}, {title: "Prepare a flake.lock update", ...prepareNetworked}, async () => {
  const workspace = await createWorkspace();
  try {
    const updated = runAllowed("nix", ["flake", "update", "--flake", workspace], workspace, 300_000);
    if (updated.status !== 0) return result(updated);
    const changes = await snapshotChanges(workspace, ["flake.lock"]);
    if (changes.length === 0) return result({kind: "no-op", message: "The flake lock file is already current.", command: updated.command});
    const operation = createOperation("flake-lock-update", changes);
    return result({...operationSummary(operation), diff: changes.map(unifiedDiff).join("\n"), command: updated.command});
  } finally {
    await rm(workspace, {recursive: true, force: true});
  }
});

server.tool("validate_flake", "Run the read-only flake check on the checkout, or on a prepared patch, format, or flake-lock operation without applying it. Omitting both arguments validates the current checkout; a prepare_working_tree_commit ID is not eligible here.", {operationId: z.string().optional().describe("A patch, format, or flake-lock operation ID. A working-tree operation ID is not resolvable here and reports as invalid or stale."), approvalHash: z.string().optional().describe("Required together with operationId; an approval hash alone is rejected.")}, {title: "Validate the flake", ...inspectNetworked}, async ({operationId, approvalHash}) => {
  if (!operationId && approvalHash) fail("An approval hash requires an operation ID.");
  if (!operationId) return result(runAllowed("nix", ["flake", "check", "--no-build", "--show-trace"], repoRoot, 300_000));
  if (!approvalHash) fail("An approval hash is required to validate a prepared operation.");
  const operation = getOperation(operationId, approvalHash);
  const workspace = await createWorkspace();
  try {
    for (const change of operation.changes) {
      const target = resolve(workspace, change.path);
      if (change.after === null) await rm(target, {force: true});
      else {
        await mkdir(dirname(target), {recursive: true});
        await Bun.write(target, change.after);
      }
    }
    return result(runAllowed("nix", ["flake", "check", "--no-build", "--show-trace"], workspace, 300_000));
  } finally {
    await rm(workspace, {recursive: true, force: true});
  }
});

server.tool("apply_approved_patch", "Apply an exact prepared operation after its ID and approval hash have been reviewed.", {operationId: z.string().describe("Operation ID returned by a prepare tool."), approvalHash: z.string().describe("Approval hash returned with that operation ID; both are rechecked before any write.")}, {title: "Apply an approved patch", ...modifyDestructive}, async ({operationId, approvalHash}) => {
  const operation = getOperation(operationId, approvalHash);
  await ensureOperationCurrent(operation);
  for (const change of operation.changes) {
    const target = await safePath(change.path);
    if (change.after === null) await rm(target.absolute, {force: true});
    else {
      await mkdir(dirname(target.absolute), {recursive: true});
      await writeFile(target.absolute, change.after, "utf8");
    }
  }
  return result({applied: true, ...operationSummary(operation)});
});

server.tool("prepare_commits", "Suggest a one-sentence commit subject per changed file for a prepared operation that has already been applied with apply_approved_patch (verb + path, e.g. 'Add compatibility for non-agent editing.'). Writes no commits and rejects a working-tree operation; edit each subject before passing it to git_commit_files.", {operationId: z.string().describe("Operation ID from a prepare tool, already applied with apply_approved_patch."), approvalHash: z.string().describe("Approval hash returned with that operation ID.")}, {title: "Suggest commit subjects", ...inspectLocal}, async ({operationId, approvalHash}) => {
  const operation = getOperation(operationId, approvalHash);
  await ensureOperationCurrent({...operation, changes: operation.changes.map((change) => ({...change, before: change.after, beforeHash: change.afterHash}))});
  const commits = operation.changes.map((change) => {
    const {path} = change;
    const inHead = runAllowed("git", ["cat-file", "-e", `HEAD:${path}`], repoRoot).status === 0;
    let subject: string;
    if (!inHead) subject = `Add ${path}.`;
    else if (change.after === null) subject = `Remove ${path}.`;
    else subject = `Update ${path}.`;
    return {path, message: subject};
  });
  return result({kind: "commit-suggestions", operationId, approvalHash, commits});
});

server.tool("git_commit_files", "After review, create explicitly approved one-file commits for a prepared operation that has already been applied with apply_approved_patch; rejects unrelated dirty paths. Subjects end with a period.", {operationId: z.string().describe("Operation ID from a prepare tool, already applied with apply_approved_patch."), approvalHash: z.string().describe("Approval hash returned with that operation ID."), commits: z.array(z.object({
    path: z.string().describe("One path from the prepared operation, which must already have been applied with apply_approved_patch."),
    message: z.string().min(1).max(4096).describe("Commit subject ending with a period. Any further line must be a valid 'Co-authored-by: Name <email>' trailer. Screened as argv, so avoid a semicolon anywhere in the message."),
  })).min(1)}, {title: "Commit prepared files", ...modifyAdditive}, async ({operationId, approvalHash, commits}) => {
  const operation = getOperation(operationId, approvalHash);
  await ensureOperationCurrent({...operation, changes: operation.changes.map((change) => ({...change, before: change.after, beforeHash: change.afterHash}))});
  const expected = new Set(operation.changes.map((change) => change.path));
  const normalizedCommits = commits.map((commit) => ({...commit, path: safeRelativePath(commit.path)}));
  const requested = new Set(normalizedCommits.map((commit) => commit.path));
  if (normalizedCommits.length !== expected.size || requested.size !== expected.size || [...expected].some((path) => !requested.has(path))) fail("Commits must cover exactly the files in the prepared operation.");
  if (normalizedCommits.some((commit) => !validCommitMessage(commit.message))) fail("Commit messages must have a sentence-style subject ending with a period; optional lines may be valid Co-authored-by trailers.");
  assertScreenedCommitArguments(normalizedCommits);

  const status = runAllowed("git", ["status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all"], repoRoot);
  if (status.status !== 0) fail(status.stderr || "Could not inspect the working tree before committing.");
  const dirtyPaths = workingTreePaths(status.stdout);
  if (dirtyPaths.some((path) => !expected.has(path))) fail("Unrelated working-tree changes must be resolved before committing this operation.");
  const results = [];
  for (const commit of normalizedCommits) {
    const {path} = commit;
    const committed = runAllowed("git", ["add", "--all", "--", path], repoRoot);
    if (committed.status !== 0) return result(committed);
    const commitResult = runAllowed("git", ["commit", "--only", "-m", commit.message, "--", path], repoRoot, 120_000);
    results.push({path, ...commitResult});
    if (commitResult.status !== 0) break;
  }
  const ok = results.length === normalizedCommits.length && results.every((commit) => commit.status === 0);
  const partial = results.some((commit) => commit.status === 0) && results.length < normalizedCommits.length;
  if (ok) operations.delete(operationId);
  return result({
    ok,
    partial,
    beforeStatus: status,
    commits: results,
    afterStatus: runAllowed("git", ["status", "--short", "--untracked-files=all"], repoRoot),
  });
});

const transport = new StdioServerTransport();
await server.connect(transport);

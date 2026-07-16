import {McpServer} from "@modelcontextprotocol/sdk/server/mcp.js";
import {StdioServerTransport} from "@modelcontextprotocol/sdk/server/stdio.js";
import {createHash, randomUUID} from "node:crypto";
import {cp, mkdir, mkdtemp, readFile, rm, stat, writeFile} from "node:fs/promises";
import {lstatSync} from "node:fs";
import {tmpdir} from "node:os";
import {basename, dirname, relative, resolve, sep} from "node:path";
import {spawnSync} from "node:child_process";
import {z} from "zod";

const repoRoot = resolve(process.env.NIX_CONFIG_MCP_ROOT ?? process.cwd());
const deniedNames = new Set([".env", ".env.local", ".env.production", "id_rsa", "id_ed25519"]);
const deniedDirectories = new Set([".git", "secrets", "node_modules"]);
const operations = new Map<string, Operation>();
const maxFileBytes = 512 * 1024;

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

const changeSchema = z.object({
  path: z.string().min(1),
  content: z.string().nullable(),
});

function text(value: unknown) {
  return typeof value === "string" ? value : JSON.stringify(value, null, 2);
}

function result(value: unknown) {
  return {content: [{type: "text" as const, text: text(value)}]};
}

function fail(message: string): never {
  throw new Error(message);
}

function safeRelativePath(input: string): string {
  if (input.includes("\0")) fail("Paths cannot contain NUL bytes.");
  const normalized = input.replaceAll("\\", "/");
  const absolute = resolve(repoRoot, normalized);
  const rel = relative(repoRoot, absolute);
  if (rel === "" || rel === ".." || rel.startsWith(`..${sep}`) || rel.includes(`${sep}.git${sep}`)) {
    fail("The path must stay inside the repository.");
  }
  const parts = rel.split(sep);
  if (parts.some((part) => deniedNames.has(part) || part.startsWith(".env")) || parts.some((part) => deniedDirectories.has(part))) {
    fail("This path is denied by the project MCP security policy.");
  }
  if (parts.some((part) => /\.(pem|key|p12|pfx|asc)$/i.test(part))) {
    fail("Private-key and certificate paths are denied by the project MCP security policy.");
  }
  return rel.split(sep).join("/");
}

async function safePath(input: string, mustExist = false): Promise<{relative: string; absolute: string}> {
  const relativePath = safeRelativePath(input);
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
    const info = await stat(absolute);
    if (lstatSync(absolute).isSymbolicLink()) fail("Symbolic-link paths are denied to prevent repository escapes.");
  } catch (error) {
    if (mustExist || (error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  return {relative: relativePath, absolute};
}

function digest(value: string | null): string | null {
  return value === null ? null : createHash("sha256").update(value).digest("hex");
}

async function readSafeFile(path: string): Promise<string | null> {
  const target = await safePath(path);
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
      changes.push({path: relativePath, beforeHash: digest(before), before, afterHash: digest(after), after});
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

function runAllowed(command: string, args: string[], cwd: string, timeout = 120_000) {
  const allowed = new Set(["nix", "git", "rg"]);
  if (!allowed.has(command)) fail(`Command is not allowed: ${command}`);
  if (args.some((arg) => arg.includes("sudo") || arg.includes("nixos-rebuild") || arg.includes(";"))) {
    fail("The requested command contains a prohibited operation.");
  }
  const completed = spawnSync(command, args, {cwd, encoding: "utf8", timeout, maxBuffer: 4 * 1024 * 1024});
  return {
    command: [command, ...args].join(" "),
    status: completed.status,
    signal: completed.signal,
    stdout: completed.stdout ?? "",
    stderr: completed.stderr ?? "",
    timedOut: (completed.error as NodeJS.ErrnoException | undefined)?.code === "ETIMEDOUT",
  };
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

function createOperation(kind: string, changes: Change[]): Operation {
  if (changes.length === 0) fail("The proposed operation produces no changes.");
  const operation: Operation = {
    id: randomUUID(),
    hash: operationHash(kind, changes),
    kind,
    createdAt: new Date().toISOString(),
    changes,
  };
  operations.set(operation.id, operation);
  return operation;
}

async function ensureOperationCurrent(operation: Operation) {
  for (const change of operation.changes) {
    const current = await readSafeFile(change.path);
    if (digest(current) !== change.beforeHash) fail(`The file changed after preparation: ${change.path}`);
  }
}

function getOperation(id: string, approvalHash: string): Operation {
  const operation = operations.get(id);
  if (!operation || operation.hash !== approvalHash) fail("The operation ID or approval hash is invalid or stale.");
  return operation;
}

const server = new McpServer({name: "nix-config-project-mcp", version: "0.1.0"});

server.tool("read_project_overview", "Summarize the repository structure and NixOS entry points.", {}, async () => {
  const output = runAllowed("git", ["ls-files", "--cached", "--others", "--exclude-standard"], repoRoot);
  return result({repository: repoRoot, files: visibleGitLines(output.stdout).filter(Boolean).slice(0, 500), flake: "flake.nix", host: "hosts/hiraeth/default.nix"});
});

server.tool("read_project_file", "Read one non-sensitive file inside the repository.", {path: z.string()}, async ({path}) => {
  const content = await readSafeFile(path);
  if (content === null) fail("The file does not exist.");
  return result({path: safeRelativePath(path), content});
});

server.tool("find_nix_references", "Find text references in Nix files without running arbitrary shell commands.", {query: z.string().min(1), path: z.string().default(".")}, async ({query, path}) => {
  const target = safeRelativePath(path);
  return result(runAllowed("rg", ["--line-number", "--glob", "*.nix", "--glob", "!secrets/**", "--", query, target], repoRoot));
});

server.tool("get_git_status", "Return the current branch and complete non-sensitive working-tree status.", {}, async () => {
  const status = runAllowed("git", ["status", "--short", "--branch", "--untracked-files=all"], repoRoot);
  return result({...status, stdout: visibleGitLines(status.stdout).join("\n")});
});

server.tool("inspect_flake", "Inspect flake outputs using the read-only nix flake show command.", {}, async () => {
  return result(runAllowed("nix", ["flake", "show", "--json", "."], repoRoot, 120_000));
});

server.tool("prepare_patch", "Prepare exact file contents in an isolated workspace without modifying the repository.", {changes: z.array(changeSchema).min(1)}, async ({changes}) => {
  const normalized = [] as string[];
  const seen = new Set<string>();
  for (const change of changes) {
    const path = safeRelativePath(change.path);
    if (seen.has(path)) fail(`A path may appear only once in a patch: ${path}`);
    seen.add(path);
    if (change.content !== null && Buffer.byteLength(change.content, "utf8") > maxFileBytes) fail(`The proposed file is too large: ${path}`);
    const before = await readSafeFile(path);
    if (change.content === null && before === null) fail(`Cannot delete a file that does not exist: ${path}`);
    normalized.push(path);
  }
  const operation = createOperation("patch", changes.map((change, index) => {
    const path = normalized[index];
    const before = null;
    return {path, beforeHash: digest(before), before, afterHash: digest(change.content), after: change.content};
  }));
  for (const change of operation.changes) {
    const before = await readSafeFile(change.path);
    change.before = before;
    change.beforeHash = digest(before);
  }
  const effectiveChanges = operation.changes.filter((change) => change.beforeHash !== change.afterHash);
  if (effectiveChanges.length !== operation.changes.length) fail("The proposed patch contains no-op changes.");
  operation.hash = operationHash(operation.kind, operation.changes);
  operations.set(operation.id, operation);
  return result({...operationSummary(operation), diff: operation.changes.map(unifiedDiff).join("\n")});
});

server.tool("prepare_format", "Run the flake formatter in an isolated workspace and return the resulting patch.", {paths: z.array(z.string()).default([])}, async ({paths}) => {
  const workspace = await createWorkspace();
  try {
    const formatted = runAllowed("nix", ["fmt", "."], workspace, 120_000);
    if (formatted.status !== 0) return result(formatted);
    const allPaths = runAllowed("git", ["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.nix"], repoRoot).stdout.split("\n").filter(Boolean);
    const selected = paths.length ? paths.map(safeRelativePath) : allPaths;
    const changes = await snapshotChanges(workspace, selected);
    if (changes.length === 0) return result({message: "Formatting produced no changes.", command: formatted.command});
    const operation = createOperation("format", changes);
    return result({...operationSummary(operation), diff: changes.map(unifiedDiff).join("\n"), command: formatted.command});
  } finally {
    await rm(workspace, {recursive: true, force: true});
  }
});

server.tool("prepare_flake_lock_update", "Update flake.lock in an isolated workspace and return only that file's patch.", {}, async () => {
  const workspace = await createWorkspace();
  try {
    const updated = runAllowed("nix", ["flake", "update", "--flake", workspace], workspace, 300_000);
    if (updated.status !== 0) return result(updated);
    const changes = await snapshotChanges(workspace, ["flake.lock"]);
    if (changes.length === 0) return result({message: "The flake lock file is already current.", command: updated.command});
    const operation = createOperation("flake-lock-update", changes);
    return result({...operationSummary(operation), diff: changes.map(unifiedDiff).join("\n"), command: updated.command});
  } finally {
    await rm(workspace, {recursive: true, force: true});
  }
});

server.tool("validate_flake", "Run the repository's read-only flake check, optionally against a prepared operation.", {operationId: z.string().optional(), approvalHash: z.string().optional()}, async ({operationId, approvalHash}) => {
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

server.tool("apply_approved_patch", "Apply an exact prepared operation after its ID and approval hash have been reviewed.", {operationId: z.string(), approvalHash: z.string()}, async ({operationId, approvalHash}) => {
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

server.tool("prepare_commits", "Suggest one sentence-style commit message for each file changed by a prepared operation.", {operationId: z.string(), approvalHash: z.string()}, async ({operationId, approvalHash}) => {
  const operation = getOperation(operationId, approvalHash);
  await ensureOperationCurrent({...operation, changes: operation.changes.map((change) => ({...change, before: change.after, beforeHash: change.afterHash}))});
  return result({operationId, approvalHash, commits: operation.changes.map((change) => ({path: change.path, message: `Update ${basename(change.path)}.`}))});
});

server.tool("git_commit_files", "Create explicitly approved one-file commits for a prepared operation.", {operationId: z.string(), approvalHash: z.string(), commits: z.array(z.object({path: z.string(), message: z.string().min(1).max(72)})).min(1)}, async ({operationId, approvalHash, commits}) => {
  const operation = getOperation(operationId, approvalHash);
  await ensureOperationCurrent({...operation, changes: operation.changes.map((change) => ({...change, before: change.after, beforeHash: change.afterHash}))});
  const status = runAllowed("git", ["status", "--porcelain=v1", "--untracked-files=all"], repoRoot);
  const expected = new Set(operation.changes.map((change) => change.path));
  const requested = new Set(commits.map((commit) => safeRelativePath(commit.path)));
  if (requested.size !== expected.size || [...expected].some((path) => !requested.has(path))) fail("Commits must cover exactly the files in the prepared operation.");
  const dirtyPaths = visibleGitLines(status.stdout)
    .filter((line) => line && !line.startsWith("##"))
    .map((line) => line.slice(3).split(" -> ").at(-1)?.trim())
    .filter((path): path is string => Boolean(path));
  if (dirtyPaths.some((path) => !expected.has(path))) fail("Unrelated working-tree changes must be resolved before committing this operation.");
  const results = [];
  for (const commit of commits) {
    const path = safeRelativePath(commit.path);
    if (!commit.message.endsWith(".") || /\n|Co-authored-by:/i.test(commit.message)) fail("Commit messages must be one sentence, end with a period, and contain no co-author trailer.");
    const committed = runAllowed("git", ["add", "--", path], repoRoot);
    if (committed.status !== 0) return result(committed);
    const commitResult = runAllowed("git", ["commit", "--only", "-m", commit.message, "--", path], repoRoot, 120_000);
    results.push({path, ...commitResult});
    if (commitResult.status !== 0) break;
  }
  return result({beforeStatus: status, commits: results, afterStatus: runAllowed("git", ["status", "--short", "--untracked-files=all"], repoRoot)});
});

const transport = new StdioServerTransport();
await server.connect(transport);

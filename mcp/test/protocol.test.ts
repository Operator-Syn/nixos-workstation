import {afterEach, describe, expect, test} from "bun:test";
import {spawnSync} from "node:child_process";
import {mkdtemp, mkdir, rm, writeFile} from "node:fs/promises";

type JsonRpcMessage = {
  id?: number;
  result?: {content?: Array<{text?: string}>; isError?: boolean};
};

const children: Bun.Subprocess[] = [];
const temporaryRepositories: string[] = [];

function runGit(cwd: string, args: string[]) {
  const result = spawnSync("git", args, {cwd, encoding: "utf8"});
  if (result.status !== 0) throw new Error(result.stderr || `git ${args.join(" ")} failed`);
  return result;
}

async function createTemporaryRepository() {
  const repository = await mkdtemp(`${process.cwd()}/.nix-config-mcp-protocol-`);
  temporaryRepositories.push(repository);
  runGit(repository, ["init", "--quiet"]);
  runGit(repository, ["config", "user.email", "test@example.invalid"]);
  runGit(repository, ["config", "user.name", "MCP Test"]);
  await writeFile(`${repository}/tracked.txt`, "before\n");
  await writeFile(`${repository}/removed.txt`, "remove me\n");
  runGit(repository, ["add", "--all"]);
  runGit(repository, ["commit", "--quiet", "-m", "Initial test state."]);
  await writeFile(`${repository}/tracked.txt`, "after\n");
  await rm(`${repository}/removed.txt`);
  await writeFile(`${repository}/added.txt`, "new file\n");
  return repository;
}

async function startServer(options: {cwd?: string; env?: Record<string, string | undefined>; entry?: string} = {}) {
  const child = Bun.spawn(["bun", options.entry ?? "mcp/src/server.ts"], {
    cwd: options.cwd ?? process.cwd(),
    env: options.env ?? process.env,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  children.push(child);
  const reader = child.stdout.getReader();
  let buffer = "";

  async function readResponse(id: number): Promise<JsonRpcMessage> {
    for (;;) {
      while (buffer.includes("\n")) {
        const index = buffer.indexOf("\n");
        const line = buffer.slice(0, index);
        buffer = buffer.slice(index + 1);
        if (!line) continue;
        const message = JSON.parse(line) as JsonRpcMessage;
        if (message.id === id) return message;
      }
      const next = await reader.read();
      if (next.done) throw new Error("The MCP server exited before responding.");
      buffer += new TextDecoder().decode(next.value);
    }
  }

  async function call(id: number, method: string, params: unknown) {
    child.stdin.write(`${JSON.stringify({jsonrpc: "2.0", id, method, params})}\n`);
    await child.stdin.flush();
    return readResponse(id);
  }

  return {child, call};
}

afterEach(async () => {
  for (const child of children.splice(0)) child.kill();
  await Promise.all(temporaryRepositories.splice(0).map((repository) => rm(repository, {recursive: true, force: true})));
});

describe("MCP stdio workflow", () => {
  test("initializes and exposes the project tools", async () => {
    const server = await startServer();
    const initialized = await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });
    expect(initialized.result?.content).toBeUndefined();
    expect(initialized.result).toBeDefined();

    const listed = await server.call(2, "tools/list", {});
    expect(listed.result).toBeDefined();
    const listedText = JSON.stringify(listed);
    for (const name of ["audit_documentation", "validate_mcp", "validate_repository", "prepare_working_tree_commit", "git_commit_working_tree"]) expect(listedText).toContain(name);
    const authority = await server.call(3, "tools/call", {name: "read_authority_contract", arguments: {}});
    expect(authority.result?.content?.[0]?.text).toContain("repositoryBoundary");
    expect(authority.result?.content?.[0]?.text).not.toContain("operationId");
    expect(authority.result?.content?.[0]?.text).not.toContain("approvalHash");
    const contract = await server.call(4, "tools/call", {name: "validate_declarative_contract", arguments: {}});
    expect(contract.result?.content?.[0]?.text).toContain('"valid": true');
    expect(contract.result?.content?.[0]?.text).not.toContain("operationId");
    expect(contract.result?.content?.[0]?.text).not.toContain("approvalHash");
    const audit = await server.call(5, "tools/call", {name: "audit_documentation", arguments: {}});
    expect(audit.result?.content?.[0]?.text).toContain("filesScanned");
    expect(audit.result?.content?.[0]?.text).not.toContain("operationId");
  });

  test("resolves the repository root when launched outside the checkout", async () => {
    const env = {...process.env};
    delete env.NIX_CONFIG_MCP_ROOT;
    const server = await startServer({
      cwd: "/home/yashindo",
      entry: "/home/yashindo/nix-config/mcp/src/server.ts",
      env,
    });
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const overview = await server.call(2, "tools/call", {
      name: "read_project_overview",
      arguments: {},
    });
    const payload = JSON.parse(overview.result?.content?.[0]?.text ?? "{}");
    expect(payload.repository).toBe("/home/yashindo/nix-config");
  });

  test("rejects denied paths and stale approvals", async () => {
    const server = await startServer();
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const denied = await server.call(2, "tools/call", {
      name: "read_project_file",
      arguments: {path: "../etc/passwd"},
    });
    expect(denied.result?.isError).toBe(true);

    const prepared = await server.call(3, "tools/call", {
      name: "prepare_patch",
      arguments: {changes: [{path: "mcp/test/protocol-temp.txt", content: "temporary\n"}]},
    });
    const operation = JSON.parse(prepared.result?.content?.[0]?.text ?? "{}");
    const stale = await server.call(4, "tools/call", {
      name: "apply_approved_patch",
      arguments: {operationId: operation.operationId, approvalHash: "stale"},
    });
    expect(stale.result?.isError).toBe(true);
  });

  test("reviews and commits an already-dirty working tree only after approval", async () => {
    const repository = await createTemporaryRepository();
    const server = await startServer({env: {...process.env, NIX_CONFIG_MCP_ROOT: repository}});
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const prepared = await server.call(2, "tools/call", {
      name: "prepare_working_tree_commit",
      arguments: {},
    });
    expect(prepared.result?.isError).not.toBe(true);
    const operation = JSON.parse(prepared.result?.content?.[0]?.text ?? "{}");
    expect(operation.kind).toBe("working-tree-commit");
    expect(operation.paths).toEqual(["added.txt", "removed.txt", "tracked.txt"]);
    expect(operation.diff).toContain("added.txt");
    expect(operation.diff).toContain("removed.txt");
    expect(operation.diff).toContain("tracked.txt");

    const committed = await server.call(3, "tools/call", {
      name: "git_commit_working_tree",
      arguments: {
        operationId: operation.operationId,
        approvalHash: operation.approvalHash,
        commits: operation.paths.map((path) => ({path, message: `Commit ${path}.`})),
      },
    });
    expect(committed.result?.isError).not.toBe(true);
    const result = JSON.parse(committed.result?.content?.[0]?.text ?? "{}");
    expect(result.commits.every((c) => c.status === 0)).toBe(true);
    expect(result.afterStatus.stdout.trim()).toBe("");
    expect(result.fileCount).toBe(3);
    expect(runGit(repository, ["rev-list", "--count", "HEAD"]).stdout.trim()).toBe("4");
    expect(runGit(repository, ["log", "--pretty=%s"]).stdout).toContain("Commit tracked.txt.");
  });

  test("commits deletions and untracked files as separate per-file commits when staged", async () => {
    const repository = await createTemporaryRepository();
    // Stage the deletions so the MCP sees them as staged removals (the reorg shape).
    runGit(repository, ["rm", "--", "removed.txt"]);
    runGit(repository, ["add", "--", "added.txt"]);
    const server = await startServer({env: {...process.env, NIX_CONFIG_MCP_ROOT: repository}});
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const prepared = await server.call(2, "tools/call", {name: "prepare_working_tree_commit", arguments: {}});
    expect(prepared.result?.isError).not.toBe(true);
    const operation = JSON.parse(prepared.result?.content?.[0]?.text ?? "{}");
    expect(operation.paths.sort()).toEqual(["added.txt", "removed.txt", "tracked.txt"]);

    const committed = await server.call(3, "tools/call", {
      name: "git_commit_working_tree",
      arguments: {
        operationId: operation.operationId,
        approvalHash: operation.approvalHash,
        commits: operation.paths.map((path) => ({path, message: `Commit ${path}.`})),
      },
    });
    expect(committed.result?.isError).not.toBe(true);
    const result = JSON.parse(committed.result?.content?.[0]?.text ?? "{}");
    expect(result.commits.every((c) => c.status === 0)).toBe(true);
    expect(result.fileCount).toBe(3);
    expect(runGit(repository, ["rev-list", "--count", "HEAD"]).stdout.trim()).toBe("4");
    expect(JSON.parse(committed.result.content[0].text).afterStatus.stdout.trim()).toBe("");
  });

  test("rejects a protected dirty path such as a private key instead of hiding it from review", async () => {
    const repository = await createTemporaryRepository();
    await writeFile(`${repository}/id_ed25519`, "protected key\n");
    const server = await startServer({env: {...process.env, NIX_CONFIG_MCP_ROOT: repository}});
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const prepared = await server.call(2, "tools/call", {
      name: "prepare_working_tree_commit",
      arguments: {},
    });
    expect(prepared.result?.isError).toBe(true);
  });

  test("includes secret changes in the reviewed working-tree snapshot when explicitly requested", async () => {
    const repository = await createTemporaryRepository();
    await mkdir(`${repository}/secrets`);
    await writeFile(`${repository}/secrets/gh.yaml`, "sops: {}\n");
    const server = await startServer({env: {...process.env, NIX_CONFIG_MCP_ROOT: repository}});
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const prepared = await server.call(2, "tools/call", {
      name: "prepare_working_tree_commit",
      arguments: {},
    });
    expect(prepared.result?.isError).not.toBe(true);
    const operation = JSON.parse(prepared.result?.content?.[0]?.text ?? "{}");
    expect(operation.paths).toContain("secrets/gh.yaml");
  });

  test("rejects Git pathspec magic filenames before commit scoping can diverge", async () => {
    const repository = await createTemporaryRepository();
    await writeFile(`${repository}/:(top)unrelated`, "literal filename\n");
    const server = await startServer({env: {...process.env, NIX_CONFIG_MCP_ROOT: repository}});
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const prepared = await server.call(2, "tools/call", {
      name: "prepare_working_tree_commit",
      arguments: {},
    });
    expect(prepared.result?.isError).toBe(true);
  });

  test("rejects a working-tree commit when the reviewed tree changes", async () => {
    const repository = await createTemporaryRepository();
    const server = await startServer({env: {...process.env, NIX_CONFIG_MCP_ROOT: repository}});
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const prepared = await server.call(2, "tools/call", {
      name: "prepare_working_tree_commit",
      arguments: {},
    });
    const operation = JSON.parse(prepared.result?.content?.[0]?.text ?? "{}");
    await writeFile(`${repository}/tracked.txt`, "changed after review\n");

    const committed = await server.call(3, "tools/call", {
      name: "git_commit_working_tree",
      arguments: {
        operationId: operation.operationId,
        approvalHash: operation.approvalHash,
        commits: [{path: "tracked.txt", message: "Commit stale review."}],
      },
    });
    expect(committed.result?.isError).toBe(true);
    expect(runGit(repository, ["log", "-1", "--pretty=%s"]).stdout.trim()).toBe("Initial test state.");
  });

  test("enforces one commit per reviewed file and rejects a partial or merged set", async () => {
    const repository = await createTemporaryRepository();
    const server = await startServer({env: {...process.env, NIX_CONFIG_MCP_ROOT: repository}});
    await server.call(1, "initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {name: "test", version: "1"},
    });

    const prepared = await server.call(2, "tools/call", {name: "prepare_working_tree_commit", arguments: {}});
    const operation = JSON.parse(prepared.result?.content?.[0]?.text ?? "{}");

    const partial = await server.call(3, "tools/call", {
      name: "git_commit_working_tree",
      arguments: {
        operationId: operation.operationId,
        approvalHash: operation.approvalHash,
        commits: operation.paths.slice(0, 1).map((path) => ({path, message: `Commit ${path}.`})),
      },
    });
    expect(partial.result?.isError).toBe(true);

    const full = await server.call(4, "tools/call", {
      name: "git_commit_working_tree",
      arguments: {
        operationId: operation.operationId,
        approvalHash: operation.approvalHash,
        commits: operation.paths.map((path) => ({path, message: `Commit ${path}.`})),
      },
    });
    expect(full.result?.isError).not.toBe(true);
    const result = JSON.parse(full.result?.content?.[0]?.text ?? "{}");
    expect(result.fileCount).toBe(3);
    expect(runGit(repository, ["rev-list", "--count", "HEAD"]).stdout.trim()).toBe("4");
  });
});

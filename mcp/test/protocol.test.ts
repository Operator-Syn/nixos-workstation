import {afterEach, describe, expect, test} from "bun:test";

type JsonRpcMessage = {
  id?: number;
  result?: {content?: Array<{text?: string}>; isError?: boolean};
};

const children: Bun.Subprocess[] = [];

async function startServer() {
  const child = Bun.spawn(["bun", "mcp/src/server.ts"], {
    cwd: process.cwd(),
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

afterEach(() => {
  for (const child of children.splice(0)) child.kill();
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
    const authority = await server.call(3, "tools/call", {name: "read_authority_contract", arguments: {}});
    expect(authority.result?.content?.[0]?.text).toContain("repositoryBoundary");
    expect(authority.result?.content?.[0]?.text).not.toContain("operationId");
    expect(authority.result?.content?.[0]?.text).not.toContain("approvalHash");
    const contract = await server.call(4, "tools/call", {name: "validate_declarative_contract", arguments: {}});
    expect(contract.result?.content?.[0]?.text).toContain('"valid": true');
    expect(contract.result?.content?.[0]?.text).not.toContain("operationId");
    expect(contract.result?.content?.[0]?.text).not.toContain("approvalHash");
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
});

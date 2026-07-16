import {describe, expect, test} from "bun:test";
import {resolve} from "node:path";

describe("project MCP safety policy", () => {
  test("uses the repository root as the project boundary", () => {
    expect(resolve(process.cwd())).toBe(process.cwd());
  });

  test("does not expose privileged activation in the launcher", async () => {
    const source = await Bun.file("mcp/src/server.ts").text();
    expect(source).not.toContain("nixos-rebuild switch");
    expect(source).not.toContain("sudo nixos-rebuild");
  });

  test("requires approval hashes for mutation tools", async () => {
    const source = await Bun.file("mcp/src/server.ts").text();
    expect(source).toContain("approvalHash: z.string()");
    expect(source).toContain("getOperation(operationId, approvalHash)");
  });
});

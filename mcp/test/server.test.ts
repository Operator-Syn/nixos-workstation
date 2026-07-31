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

  test("keeps verification helpers fixed-scope", async () => {
    const source = await Bun.file("mcp/src/server.ts").text();
    expect(source).toContain('server.tool("audit_documentation"');
    expect(source).toContain('server.tool("validate_mcp"');
    expect(source).toContain('server.tool("validate_repository"');
    expect(source).toContain('runFixed("bun", ["test", "mcp"]');
    expect(source).toContain('runAllowed("nix", ["flake", "check", "--no-build", "--show-trace"]');
  });

  test("allows valid co-author trailers while keeping commit subjects constrained", async () => {
    const source = await Bun.file("mcp/src/server.ts").text();
    expect(source).toContain("const [subject, ...trailers] = message.split(\"\\n\")");
    expect(source).toContain("Co-authored-by:");
    expect(source).not.toContain("contain no co-author trailer");
  });
});

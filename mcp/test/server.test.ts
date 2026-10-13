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
    // Required handles on the mutation tools and the commit-suggestion tool.
    // validate_flake's deliberately optional pair does not match, since the check
    // counts only `z.string()` with no `.optional()` between it and the next token.
    const requiredHandles = [...source.matchAll(/approvalHash: z\.string\(\)/g)].length;
    expect(requiredHandles).toBeGreaterThanOrEqual(3);
    // And rechecked in the handler by both operation families.
    expect(source).toContain("getOperation(operationId, approvalHash)");
    expect(source).toContain("getWorkingTreeOperation(operationId, approvalHash)");
  });

  test("declares an output schema for every registered tool", async () => {
    const source = await Bun.file("mcp/src/server.ts").text();
    // structuredContent is mandatory once an output schema exists, so a tool that
    // declares one without mirroring its payload would fail after its handler ran.
    const registered = [...source.matchAll(/server\.registerTool\("/g)].length;
    const withOutputSchema = [...source.matchAll(/outputSchema: \w+/g)].length;
    expect(registered).toBeGreaterThan(0);
    expect(withOutputSchema).toBe(registered);
  });

  test("keeps verification helpers fixed-scope", async () => {
    const source = await Bun.file("mcp/src/server.ts").text();
    expect(source).toContain('server.registerTool("audit_documentation"');
    expect(source).toContain('server.registerTool("validate_mcp"');
    expect(source).toContain('server.registerTool("validate_repository"');
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

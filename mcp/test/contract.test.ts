import {describe, expect, test} from "bun:test";
import {validateDeclarativeContract, type ContractSources} from "../src/contract.ts";

const validSources: ContractSources = {
  "mcp/src/server.ts": `const repoRoot = resolve(); function safeRelativePath() { return "The path must stay inside the repository."; } const deniedDirectories = new Set([".git", "secrets"]); const deniedNames = new Set([".env"]); const allowed = new Set(["nix", "git", "rg"]); spawnSync(command, args, {cwd});`,
};

describe("declarative contract validator", () => {
  test("accepts the repository safety contract", () => {
    expect(validateDeclarativeContract(validSources).valid).toBe(true);
  });

  test("preserves MCP security boundaries", () => {
    const sources = {...validSources, "mcp/src/server.ts": `${validSources["mcp/src/server.ts"]}\nallowed.add("sudo");`};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "mcp-no-privileged-allowlist")?.severity).toBe("error");
  });
});

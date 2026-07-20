import {describe, expect, test} from "bun:test";
import {validateDeclarativeContract, type ContractSources} from "../src/contract.ts";

const validSources: ContractSources = {
  "modules/nixos/security/home-acl.nix": `
systemd.services.home-acl-reconcile = {};
systemd.timers.home-acl-reconcile = { Persistent = true; };
lock=/run/lock/home-acl-reconcile.lock
flock 9
hermes-repair-acls: systemctl start home-acl-reconcile.service
`,
  "hosts/hiraeth/default.nix": `
services.homeAcl.policies = [
  { name = "hermes-home-audit"; reader = "feilhann"; readerGroup = "hermes-audit-readonly"; target = "yashindo"; excludeDirectories = ["Git"]; }
  { name = "hermes-projects-write"; readerGroup = "hermes-projects-write"; }
  { name = "feilhann-home-admin"; reader = "yashindo"; readerGroup = "feilhann-home-admin"; target = "feilhann"; access = "read-write"; }
];
systemd.services.home-acl-reconcile = { after = ["hermes-desktop-backend.service" "systemd-tmpfiles-resetup.service"]; };
`,
  "modules/nixos/users/feilhann.nix": `users.groups."hermes-projects-write" = { members = ["feilhann"]; }; users.groups."feilhann-home-admin" = { members = ["yashindo"]; }; d /home/feilhann 0770`,
  "modules/nixos/hermes.nix": `d /home/feilhann/.hermes 0770 d /home/feilhann/.hermes/browser-profile 0770 SupplementaryGroups = [ "hermes-projects-write" ]; ProtectHome = "read-only"; HERMES_MANAGED_DIR=/etc/hermes`,
  "modules/nixos/scripts.nix": `systemctl start home-acl-reconcile.service`,
  "mcp/src/server.ts": `const repoRoot = resolve(); function safeRelativePath() { return "The path must stay inside the repository."; } const deniedDirectories = new Set([".git", "secrets"]); const deniedNames = new Set([".env"]); const allowed = new Set(["nix", "git", "rg"]); spawnSync(command, args, {cwd});`,
};

describe("declarative contract validator", () => {
  test("accepts the current contract shape", () => {
    expect(validateDeclarativeContract(validSources).valid).toBe(true);
  });

  test("detects missing unified reconciliation and lock", () => {
    const sources = {...validSources, "modules/nixos/security/home-acl.nix": ""};
    const result = validateDeclarativeContract(sources);
    expect(result.findings.filter((finding) => finding.severity === "error").map((finding) => finding.id)).toEqual(expect.arrayContaining(["unified-service", "unified-timer", "global-lock"]));
  });

  test("detects audit home visibility sandbox regression", () => {
    const sources = {...validSources, "modules/nixos/hermes.nix": validSources["modules/nixos/hermes.nix"].replace('ProtectHome = "read-only";', "ProtectHome = true;")};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "audit-home-visibility")?.severity).toBe("error");
  });

  test("detects broad Git ACL scope and missing backend group", () => {
    const sources = {
      ...validSources,
      "hosts/hiraeth/default.nix": validSources["hosts/hiraeth/default.nix"].replace('excludeDirectories = ["Git"]', "excludeDirectories = []"),
      "modules/nixos/hermes.nix": validSources["modules/nixos/hermes.nix"].replace('"hermes-projects-write"', ""),
    };
    const result = validateDeclarativeContract(sources);
    expect(result.findings.map((finding) => finding.id)).toEqual(expect.arrayContaining(["git-exclusion", "backend-write-group"]));
  });

  test("detects missing full-home admin policy", () => {
    const sources = {
      ...validSources,
      "hosts/hiraeth/default.nix": validSources["hosts/hiraeth/default.nix"].replace('  { name = "feilhann-home-admin"; reader = "yashindo"; readerGroup = "feilhann-home-admin"; target = "feilhann"; access = "read-write"; }\n', ""),
    };
    const result = validateDeclarativeContract(sources);
    expect(result.findings.map((finding) => finding.id)).toEqual(expect.arrayContaining(["policy-order", "full-home-admin-group", "full-home-admin-policy"]));
  });

  test("detects superseded narrow policies", () => {
    const sources = {
      ...validSources,
      "hosts/hiraeth/default.nix": `${validSources["hosts/hiraeth/default.nix"]}\n{ name = "hermes-plans-readonly"; }`,
    };
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "superseded-home-policies")?.severity).toBe("error");
  });

  test("detects tmpfiles modes that would collapse the admin ACL mask", () => {
    const sources = {
      ...validSources,
      "modules/nixos/users/feilhann.nix": validSources["modules/nixos/users/feilhann.nix"].replace("0770", "0750"),
      "modules/nixos/hermes.nix": validSources["modules/nixos/hermes.nix"].replaceAll("0770", "0710"),
    };
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "tmpfiles-home-mask")?.severity).toBe("error");
  });

  test("detects obsolete rb policy service references", () => {
    const sources = {...validSources, "modules/nixos/scripts.nix": "systemctl start hermes-plans-readonly-acl.service"};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "rebuild-entrypoint")?.severity).toBe("error");
  });

  test("detects generation-sensitive rb helper paths", () => {
    const sources = {...validSources, "modules/nixos/scripts.nix": "if ! /run/current-system/sw/bin/hermes-repair-acls; then true; fi"};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "rebuild-entrypoint")?.severity).toBe("error");
  });

  test("detects privileged MCP command expansion", () => {
    const sources = {...validSources, "mcp/src/server.ts": `${validSources["mcp/src/server.ts"]}\nallowed.add("sudo");`};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "mcp-no-privileged-allowlist")?.severity).toBe("error");
  });

  test("detects activation command expansion", () => {
    const sources = {...validSources, "mcp/src/server.ts": `${validSources["mcp/src/server.ts"]}\nallowed.add("nixos-rebuild");`};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "mcp-no-privileged-allowlist")?.severity).toBe("error");
  });
});

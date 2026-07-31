import {describe, expect, test} from "bun:test";
import {validateDeclarativeContract, type ContractSources} from "../src/contract.ts";

const validSources: ContractSources = {
  "hosts/hiraeth/default.nix": `imports = [ ../../modules/nixos/hermes.nix ];
sops.secrets.gh_token = {};
sops.secrets.gh_operator_syn_token = {};`,
  "modules/nixos/users/yashindo.nix": `users.users.yashindo = { uid = 1000; };`,
  "modules/nixos/hermes.nix": `
pkgs.dockerTools.buildLayeredImage = true;
virtualisation.oci-containers.backend = "docker";
virtualisation.oci-containers.containers.hermes-backend = {
  imageFile = hermesBackendImage;
  user = "config.users.users.\${username}.uid:config.users.groups.users.gid";
  environmentFiles = ["/run/hermes/dashboard-token"];
  volumes = ["\${homeDirectory}:\${homeDirectory}:rw"];
extraOptions = ["--network=host"];
"--host"
127.0.0.1
};
export HERMES_HOME=\${hermesHome}
hermes-dashboard-token.service
cwd = homeDirectory
gh-feilhann
gh-operator-syn
`,
  "modules/nixos/graphify.nix": `User = "yashindo";`,
  "modules/nixos/hermes-graphify.nix": `virtualisation.oci-containers.containers.hermes-backend = {};`,
  "modules/nixos/obsidian-hermes-vault.nix": `users.users.yashindo.extraGroups = ["obsidian-hermes"];`,
  "home/yashindo/apps/hermes-desktop.nix": `hermes-desktop-launcher`,
  "flake.nix": `home-manager.users.yashindo = import ./home/yashindo;`,
  "mcp/src/server.ts": `const repoRoot = resolve(); function safeRelativePath() { return "The path must stay inside the repository."; } const deniedDirectories = new Set([".git", "secrets"]); const deniedNames = new Set([".env"]); const allowed = new Set(["nix", "git", "rg"]); spawnSync(command, args, {cwd});`,
};

describe("declarative contract validator", () => {
  test("accepts the fresh Hermes container contract", () => {
    expect(validateDeclarativeContract(validSources).valid).toBe(true);
  });

  test("detects a non-reproducible or missing OCI backend", () => {
    const sources = {...validSources, "modules/nixos/hermes.nix": validSources["modules/nixos/hermes.nix"].replace("pkgs.dockerTools.buildLayeredImage", "pkgs.writeText")};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "oci-backend")?.severity).toBe("error");
  });

  test("detects a home mount regression", () => {
    const sources = {...validSources, "modules/nixos/hermes.nix": validSources["modules/nixos/hermes.nix"].replace('"${homeDirectory}:${homeDirectory}:rw"', '"${homeDirectory}:${homeDirectory}:ro"')};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "home-mount")?.severity).toBe("error");
  });

  test("detects Feilhann references returning to the host wiring", () => {
    const sources = {...validSources, "hosts/hiraeth/default.nix": `${validSources["hosts/hiraeth/default.nix"]} users/feilhann.nix`};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "legacy-user-removed")?.severity).toBe("error");
  });

  test("detects a backend that is not tied to the declarative UID", () => {
    const sources = {...validSources, "modules/nixos/users/yashindo.nix": "users.users.yashindo = {};"};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "uid-gid")?.severity).toBe("error");
  });

  test("detects missing explicit GitHub account wrappers", () => {
    const sources = {...validSources, "modules/nixos/hermes.nix": validSources["modules/nixos/hermes.nix"].replace("gh-operator-syn", "")};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "github-cli-accounts")?.severity).toBe("error");
  });

  test("preserves MCP security boundaries", () => {
    const sources = {...validSources, "mcp/src/server.ts": `${validSources["mcp/src/server.ts"]}\nallowed.add("sudo");`};
    expect(validateDeclarativeContract(sources).findings.find((finding) => finding.id === "mcp-no-privileged-allowlist")?.severity).toBe("error");
  });
});

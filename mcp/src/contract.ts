export type ContractSources = Record<string, string>;

export type ContractFinding = {
  id: string;
  severity: "ok" | "warning" | "error";
  message: string;
  path?: string;
  line?: number;
};

export const authorityContract = {
  repositoryBoundary: "The MCP may read and mutate only approved files inside the configured repository root.",
  allowedMutations: [
    "Prepare exact repository patches without modifying the checkout; format and lock-update preparation uses an isolated workspace.",
    "Apply an explicitly approved patch after rechecking file hashes.",
    "Create explicitly approved one-file commits for prepared changes.",
    "Review the complete visible dirty working tree and create one explicitly approved commit after rechecking its snapshot.",
  ],
  userOwnedOperations: [
    "sudo and NixOS activation",
    "reboot and live systemd/container verification",
    "runtime verification against /run, user homes, credentials, and the vault",
  ],
  declarativeRuntimeRules: [
    "Hermes container configuration is authoritative over manual container runs.",
    "The Hermes backend uses the pinned Nix package and a reproducible OCI image.",
    "The backend runs with Yashindo's numeric UID/GID and mounts /home/yashindo at the same path.",
    "The desktop API is exposed only on the host loopback interface.",
    "External shared roots such as /srv/obsidian/hermes-vault remain explicitly declared.",
  ],
  graphifyBoundary: "Graphify is read-only discovery; Nix source and flake checks remain authoritative.",
  protectedPaths: [
    "secrets/",
    ".env*",
    ".git/",
    "private keys and certificates",
    "/srv/obsidian/hermes-vault/40 Plans/",
  ],
  sourceOfTruth: [
    "Nix source",
    "nix flake check --no-build --show-trace",
    "built and activated system generations, verified separately",
  ],
};

function lineOf(source: string, needle: string): number | undefined {
  const index = source.indexOf(needle);
  return index < 0 ? undefined : source.slice(0, index).split("\n").length;
}

function has(source: string, needle: string): boolean {
  return source.includes(needle);
}

function find(source: string, pattern: RegExp): boolean {
  return pattern.test(source);
}

export function validateDeclarativeContract(sources: ContractSources) {
  const findings: ContractFinding[] = [];
  const check = (id: string, condition: boolean, message: string, path?: string, needle?: string) => {
    findings.push({
      id,
      severity: condition ? "ok" : "error",
      message,
      ...(path ? {path} : {}),
      ...(path && needle && lineOf(sources[path] ?? "", needle) ? {line: lineOf(sources[path] ?? "", needle)} : {}),
    });
  };

  const hermes = sources["modules/nixos/hermes.nix"] ?? "";
  const host = sources["hosts/hiraeth/default.nix"] ?? "";
  const graphify = sources["modules/nixos/graphify.nix"] ?? "";
  const hermesGraphify = sources["modules/nixos/hermes-graphify.nix"] ?? "";
  const obsidian = sources["modules/nixos/obsidian-hermes-vault.nix"] ?? "";
  const yashi = sources["modules/nixos/users/yashindo.nix"] ?? "";
  const desktop = sources["home/yashindo/apps/hermes-desktop.nix"] ?? "";
  const flake = sources["flake.nix"] ?? "";
  const mcp = sources["mcp/src/server.ts"] ?? "";
  const nixInterpolation = (name: string) => `\${${name}}`;
  const homeMount = `"${nixInterpolation("homeDirectory")}:${nixInterpolation("homeDirectory")}:rw"`;
  const userUid = `config.users.users.${nixInterpolation("username")}.uid`;
  const hermesHome = `export HERMES_HOME=${nixInterpolation("hermesHome")}`;

  check("oci-backend", has(hermes, "pkgs.dockerTools.buildLayeredImage") && has(hermes, "virtualisation.oci-containers.containers.hermes-backend"), "Hermes has a reproducible Docker OCI backend image and container declaration.", "modules/nixos/hermes.nix", "virtualisation.oci-containers.containers.hermes-backend");
  check("docker-runtime", has(hermes, 'virtualisation.oci-containers.backend = "docker"'), "Hermes explicitly selects Docker as the OCI runtime.", "modules/nixos/hermes.nix", 'virtualisation.oci-containers.backend = "docker"');
  check("home-mount", has(hermes, homeMount), "The backend mounts Yashindo's home at the same path with write access.", "modules/nixos/hermes.nix", homeMount);
  check("uid-gid", has(hermes, userUid) && has(hermes, "config.users.groups.users.gid") && has(yashi, "uid = 1000"), "The container identity is tied to Yashindo's declarative numeric UID/GID.", "modules/nixos/users/yashindo.nix", "uid = 1000");
  check("localhost-backend", has(hermes, 'extraOptions = ["--network=host"]') && has(hermes, '"--host"') && has(hermes, '127.0.0.1'), "The backend remains reachable only through host loopback.", "modules/nixos/hermes.nix", 'extraOptions = ["--network=host"]');
  check("dashboard-token", has(hermes, "hermes-dashboard-token.service") && has(hermes, "environmentFiles = [\"/run/hermes/dashboard-token\"]"), "The desktop/backend dashboard token remains declaratively generated and injected.", "modules/nixos/hermes.nix", "environmentFiles = [\"/run/hermes/dashboard-token\"]");
  check("imperative-settings", !has(hermes, "environment.etc.\"hermes/config.yaml\"") && !has(hermes, "HERMES_MANAGED_DIR"), "Hermes settings are not declaratively managed; users configure them through Hermes at runtime.", "modules/nixos/hermes.nix", "environment.systemPackages");
  check("fresh-yashindo-state", has(hermes, hermesHome), "Hermes state uses Yashindo's home.", "modules/nixos/hermes.nix", hermesHome);
  check("desktop-neutral-launcher", has(desktop, "hermes-desktop-launcher") && !has(desktop, "feilhann"), "The desktop launcher is no longer Feilhann-specific.", "home/yashindo/apps/hermes-desktop.nix", "hermes-desktop-launcher");
  check("graphify-user", has(graphify, 'User = "yashindo"') && !has(graphify, 'User = "feilhann"'), "Graphify vault services run without the removed Feilhann account.", "modules/nixos/graphify.nix", 'User = "yashindo"');
  check("vault-group", has(obsidian, 'users.users.yashindo.extraGroups = ["obsidian-hermes"]') && !has(obsidian, "feilhann"), "The shared vault group has no Feilhann dependency.", "modules/nixos/obsidian-hermes-vault.nix", "obsidian-hermes");
  check("container-graphify", has(hermesGraphify, "virtualisation.oci-containers.containers.hermes-backend"), "Hermes Graphify integration extends the container declaration.", "modules/nixos/hermes-graphify.nix", "virtualisation.oci-containers.containers.hermes-backend");
  check("github-cli-accounts", has(host, "sops.secrets.gh_token") && has(host, "sops.secrets.gh_operator_syn_token") && has(hermes, "gh-feilhann") && has(hermes, "gh-operator-syn"), "Hermes has explicit SOPS-backed GitHub CLI wrappers for both accounts.", "modules/nixos/hermes.nix", "gh-feilhann");
  check("legacy-user-removed", !has(flake, "home-manager.users.feilhann") && !has(host, "users/feilhann") && !has(host, "services.homeAcl"), "The removed Feilhann user and legacy ACL/audit wiring are absent.", "flake.nix", "home-manager.users.feilhann");

  check("mcp-repo-boundary", has(mcp, "const repoRoot") && has(mcp, "safeRelativePath") && has(mcp, "The path must stay inside the repository."), "MCP paths are confined to the repository root.", "mcp/src/server.ts", "safeRelativePath");
  check("mcp-denied-paths", has(mcp, "deniedDirectories") && has(mcp, "secrets") && has(mcp, ".env"), "MCP denies repository secrets and private paths.", "mcp/src/server.ts", "deniedDirectories");
  check("mcp-no-privileged-allowlist", has(mcp, 'new Set(["nix", "git", "rg"])') && !find(mcp, /allowed\.add\(["'](?:sudo|nixos-rebuild|sh|bash)["']/), "MCP does not allow sudo, activation, or arbitrary privileged commands.", "mcp/src/server.ts", "new Set([\"nix\", \"git\", \"rg\"])");
  check("mcp-no-shell-execution", has(mcp, "spawnSync(command, args") && !has(mcp, "shell: true"), "MCP command execution does not enable a shell.", "mcp/src/server.ts", "spawnSync(command, args");

  return {
    valid: findings.every((finding) => finding.severity !== "error"),
    findings,
  };
}

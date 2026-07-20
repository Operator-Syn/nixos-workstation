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
    "Prepare exact repository patches in an isolated workspace.",
    "Apply an explicitly approved patch after rechecking file hashes.",
    "Create explicitly approved one-file commits with sentence-style messages.",
  ],
  userOwnedOperations: [
    "sudo and privileged ACL changes",
    "NixOS activation, reboot, and live systemd verification",
    "runtime verification against /run, user homes, credentials, and the vault",
  ],
  declarativeAclRules: [
    "ACL policy declarations are authoritative over manual setfacl changes.",
    "Read-only audit groups remain separate from dedicated home-admin and project-write groups.",
    "The feilhann-home-admin group grants Yashindo full access only to Feilhann's home.",
    "Broad read-only policies exclude narrower write scopes.",
    "The existing reverse audit and Git policies remain intentional exceptions.",
    "One home-acl reconciliation service and persistent timer serialize repairs.",
    "tmpfiles modes preserve required ACL masks.",
  ],
  graphifyBoundary: "Graphify is read-only discovery; Nix source and flake checks remain authoritative.",
  protectedPaths: [
    "secrets/",
    ".env*",
    ".git/",
    "private keys and certificates",
    "/srv/obsidian/hermes-vault/40 Plans/",
    "/home/feilhann/.hermes/",
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
  const add = (finding: ContractFinding) => findings.push(finding);
  const check = (id: string, condition: boolean, message: string, path?: string, needle?: string) => {
    add({
      id,
      severity: condition ? "ok" : "error",
      message,
      ...(path ? {path} : {}),
      ...(path && needle && lineOf(sources[path] ?? "", needle) ? {line: lineOf(sources[path] ?? "", needle)} : {}),
    });
  };

  const acl = sources["modules/nixos/security/home-acl.nix"] ?? "";
  const host = sources["hosts/hiraeth/default.nix"] ?? "";
  const users = sources["modules/nixos/users/feilhann.nix"] ?? "";
  const hermes = sources["modules/nixos/hermes.nix"] ?? "";
  const scripts = sources["modules/nixos/scripts.nix"] ?? "";
  const mcp = sources["mcp/src/server.ts"] ?? "";

  check("unified-service", has(acl, "systemd.services.home-acl-reconcile"), "A single home-acl-reconcile service is declared.", "modules/nixos/security/home-acl.nix", "systemd.services.home-acl-reconcile");
  check("unified-timer", has(acl, "systemd.timers.home-acl-reconcile") && has(acl, "Persistent = true"), "The unified ACL timer is persistent and declarative.", "modules/nixos/security/home-acl.nix", "systemd.timers.home-acl-reconcile");
  check("global-lock", has(acl, "home-acl-reconcile.lock") && has(acl, "flock 9"), "ACL reconciliation uses one global lock.", "modules/nixos/security/home-acl.nix", "home-acl-reconcile.lock");
  const policyOrder = ["hermes-home-audit", "hermes-projects-write", "feilhann-home-admin"];
  const policyIndexes = policyOrder.map((name) => host.indexOf(`name = \"${name}\"`));
  const policiesAreOrdered = policyIndexes.every((index, position) => index >= 0 && (position === 0 || index > policyIndexes[position - 1]));
  check("policy-order", policiesAreOrdered, "ACL policies are declared in deterministic reconciliation order.", "hosts/hiraeth/default.nix", "services.homeAcl.policies");
  check("git-exclusion", find(host, /name = "hermes-home-audit"[\s\S]{0,320}excludeDirectories = \["Git"\]/), "The broad audit policy excludes Git.", "hosts/hiraeth/default.nix", "excludeDirectories = [\"Git\"]");
  check("reverse-audit-policy", find(host, /name = "hermes-home-audit"[\s\S]{0,320}reader = "feilhann"[\s\S]{0,320}target = "yashindo"/), "The existing Feilhann-to-Yashindo audit policy remains intact.", "hosts/hiraeth/default.nix", "name = \"hermes-home-audit\"");
  check("dedicated-write-group", has(users, "hermes-projects-write") && has(host, "readerGroup = \"hermes-projects-write\""), "Git write access uses a dedicated group.", "modules/nixos/users/feilhann.nix", "hermes-projects-write");
  check("full-home-admin-group", find(users, /users\.groups\.\"feilhann-home-admin\"[\s\S]{0,160}members = \[\"yashindo\"\]/), "The full-home admin group contains only Yashindo.", "modules/nixos/users/feilhann.nix", "feilhann-home-admin");
  const fullHomeAdmin = find(host, /name = "feilhann-home-admin"[\s\S]{0,520}reader = "yashindo"[\s\S]{0,520}readerGroup = "feilhann-home-admin"[\s\S]{0,520}target = "feilhann"[\s\S]{0,520}access = "read-write"/);
  check("full-home-admin-policy", fullHomeAdmin, "Yashindo receives full read-write access to Feilhann's entire home through the dedicated group.", "hosts/hiraeth/default.nix", "name = \"feilhann-home-admin\"");
  check("full-home-admin-direction", !find(host, /name = "feilhann-home-admin"[\s\S]{0,520}reader = "feilhann"[\s\S]{0,520}target = "yashindo"/), "The full-home admin policy does not grant Feilhann broad access to Yashindo's home.", "hosts/hiraeth/default.nix", "name = \"feilhann-home-admin\"");
  check("tmpfiles-home-mask", has(users, "d /home/feilhann 0770") && has(hermes, "d /home/feilhann/.hermes 0770") && has(hermes, "d /home/feilhann/.hermes/browser-profile 0770"), "tmpfiles modes preserve the full read-write ACL masks.", "modules/nixos/users/feilhann.nix", "d /home/feilhann 0770");
  check("backend-write-group", has(hermes, '"hermes-projects-write"'), "The Hermes backend receives the project-write supplementary group.", "modules/nixos/hermes.nix", '"hermes-projects-write"');
  check("audit-home-visibility", has(hermes, 'ProtectHome = "read-only"'), "The privileged audit can inspect home ACL metadata without write access.", "modules/nixos/hermes.nix", 'ProtectHome = "read-only"');
  check("managed-hermes", has(hermes, "HERMES_MANAGED_DIR=/etc/hermes"), "Hermes uses the declarative managed configuration directory.", "modules/nixos/hermes.nix", "HERMES_MANAGED_DIR=/etc/hermes");
  const directReconcile = has(scripts, "systemctl start home-acl-reconcile.service") && !has(scripts, "/run/current-system/sw/bin/hermes-repair-acls");
  check("rebuild-entrypoint", directReconcile && has(acl, "hermes-repair-acls") && has(acl, "start home-acl-reconcile.service") && !has(scripts, "hermes-plans-readonly-acl.service"), "rb invokes the unified ACL reconciler directly without a generation-sensitive helper path.", "modules/nixos/scripts.nix", "systemctl start home-acl-reconcile.service");
  check("host-ordering", has(host, '"systemd-tmpfiles-resetup.service"') && has(host, '"hermes-desktop-backend.service"'), "The reconciler is ordered after tmpfiles resetup and Hermes backend startup.", "hosts/hiraeth/default.nix", "systemd.services.home-acl-reconcile");

  const obsolete = ["hermes-home-audit-acl.service", "feilhann-home-readonly-acl.service", "hermes-plans-readonly-acl.service", "hermes-projects-write-acl.service"];
  const obsoleteFound = obsolete.find((name) => [acl, host, scripts, hermes].some((source) => has(source, name)));
  check("obsolete-policy-units", !obsoleteFound, "Obsolete per-policy ACL service references are absent.", "modules/nixos/security/home-acl.nix");
  const superseded = ["name = \"feilhann-home-readonly\"", "name = \"hermes-plans-readonly\""];
  const supersededFound = superseded.find((name) => has(host, name));
  check("superseded-home-policies", !supersededFound, "Superseded Yashindo-to-Feilhann narrow policies are absent.", "hosts/hiraeth/default.nix");

  check("mcp-repo-boundary", has(mcp, "const repoRoot") && has(mcp, "safeRelativePath") && has(mcp, "The path must stay inside the repository."), "MCP paths are confined to the repository root.", "mcp/src/server.ts", "safeRelativePath");
  check("mcp-denied-paths", has(mcp, "deniedDirectories") && has(mcp, "secrets") && has(mcp, ".env"), "MCP denies repository secrets and private paths.", "mcp/src/server.ts", "deniedDirectories");
  check("mcp-no-privileged-allowlist", has(mcp, 'new Set(["nix", "git", "rg"])') && !find(mcp, /allowed\.add\([\"'](?:sudo|nixos-rebuild|sh|bash)[\"']/), "MCP does not allow sudo, activation, or arbitrary privileged commands.", "mcp/src/server.ts", "new Set([\"nix\", \"git\", \"rg\"])");
  check("mcp-no-shell-execution", has(mcp, "spawnSync(command, args") && !has(mcp, "shell: true"), "MCP command execution does not enable a shell.", "mcp/src/server.ts", "spawnSync(command, args");

  return {
    valid: findings.every((finding) => finding.severity !== "error"),
    findings,
  };
}

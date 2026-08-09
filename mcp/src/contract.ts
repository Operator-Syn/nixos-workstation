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
    "Nix source and flake checks remain authoritative for declarative system configuration.",
    "Live activation and runtime verification are separate from source and build validation.",
  ],
  graphifyBoundary: "Graphify is read-only discovery; Nix source and flake checks remain authoritative.",
  protectedPaths: [
    "secrets/",
    ".env*",
    ".git/",
    "private keys and certificates",
    "/srv/obsidian/",
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

  const mcp = sources["mcp/src/server.ts"] ?? "";
  check("mcp-repo-boundary", has(mcp, "const repoRoot") && has(mcp, "safeRelativePath") && has(mcp, "The path must stay inside the repository."), "MCP paths are confined to the repository root.", "mcp/src/server.ts", "safeRelativePath");
  check("mcp-denied-paths", has(mcp, "deniedDirectories") && has(mcp, "secrets") && has(mcp, ".env"), "MCP denies repository secrets and private paths.", "mcp/src/server.ts", "deniedDirectories");
  check("mcp-no-privileged-allowlist", has(mcp, 'new Set(["nix", "git", "rg"])') && !find(mcp, /allowed\.add\(["'](?:sudo|nixos-rebuild|sh|bash)["']/), "MCP does not allow sudo, activation, or arbitrary privileged commands.", "mcp/src/server.ts", "new Set([\"nix\", \"git\", \"rg\"])");
  check("mcp-no-shell-execution", has(mcp, "spawnSync(command, args") && !has(mcp, "shell: true"), "MCP command execution does not enable a shell.", "mcp/src/server.ts", "spawnSync(command, args");

  return {
    valid: findings.every((finding) => finding.severity !== "error"),
    findings,
  };
}

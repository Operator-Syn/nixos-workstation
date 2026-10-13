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
  // Kept aligned with safeRelativePath/safePath in src/server.ts. A contract that
  // lists fewer denials than the code applies is worse than no contract, because
  // agents trust it and then get unexplained failures.
  protectedPaths: [
    "secrets/ (denied by every tool except the reviewed working-tree commit path)",
    ".env* (denied except the public template vps/web-research/.env.example, which only the reviewed working-tree commit path may include)",
    ".git/ and node_modules/, at any path component",
    "private keys and certificates (id_rsa, id_ed25519, *.pem, *.key, *.p12, *.pfx, *.asc)",
    "any symbolic link, at any path component",
    "any path that escapes the repository root, contains a NUL byte, or whose normalized name begins with ':' (Git pathspec magic)",
    "/srv/obsidian/ (outside the repository boundary entirely; no tool reaches it)",
  ],
  argumentGuards: [
    "Every argument of every spawned command is screened as a substring for ';', 'sudo', and 'nixos-rebuild'. User-supplied text becomes argv, so commit subjects, paths, and search patterns are screened too; the rejection error names the token and the argument.",
    "Commit subjects must end with a period. Additional lines are permitted only as valid 'Co-authored-by: Name <email>' trailers.",
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

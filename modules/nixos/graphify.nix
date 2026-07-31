{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.graphify;
  vaultPath = "/srv/obsidian/hermes-vault";
  statePath = "/var/lib/graphify/hermes-vault";
  derivedPath = "/var/lib/graphify/hermes-derived-vault";
  graphPath = "${statePath}/graphify-out/graph.json";
  notesHelper = pkgs.writeText "hermes-graphify-notes-mcp.py" (builtins.readFile ../../scripts/hermes_graphify_mcp.py);
  vaultHelper = pkgs.writeText "graphify-vault.py" (builtins.readFile ../../scripts/graphify_vault.py);
  graphifyBuild = pkgs.writeShellScript "graphify-build-hermes-vault" ''
    set -euo pipefail

    source=${lib.escapeShellArg vaultPath}
    state=${lib.escapeShellArg statePath}
    derived=${lib.escapeShellArg derivedPath}
    vault_helper=${lib.escapeShellArg vaultHelper}
    manifest="$state/manifest.sha256"
    lock="$state/.build.lock"
    temporary="$state/.build.$$.tmp"
    old_graph="$state/.graphify-out.$$.old"
    old_derived="$state/.derived.$$.old"
    old_graph_moved=0
    old_derived_moved=0
    new_graph_installed=0
    new_derived_installed=0

    cleanup() {
      status="$?"
      ${pkgs.coreutils}/bin/rm -rf "$temporary"
      if test "$status" -ne 0; then
        if test "$new_graph_installed" -eq 1; then
          ${pkgs.coreutils}/bin/rm -rf "$state/graphify-out"
        fi
        if test "$new_derived_installed" -eq 1; then
          ${pkgs.coreutils}/bin/rm -rf "$derived"
        fi
        if test "$old_graph_moved" -eq 1 && ! test -e "$state/graphify-out"; then
          ${pkgs.coreutils}/bin/mv "$old_graph" "$state/graphify-out"
        fi
        if test "$old_derived_moved" -eq 1 && ! test -e "$derived"; then
          ${pkgs.coreutils}/bin/mv "$old_derived" "$derived"
        fi
      else
        ${pkgs.coreutils}/bin/rm -rf "$old_graph" "$old_derived"
      fi
      return "$status"
    }
    trap cleanup EXIT

    exec 9>"$lock"
    ${pkgs.util-linux}/bin/flock -n 9 || exit 0
    if test -f "$manifest" && ${pkgs.python3}/bin/python "$vault_helper" matches "$source" "$manifest"; then
      exit 0
    fi

    ${pkgs.coreutils}/bin/install -d -m 0750 "$temporary/graphify-out" "$temporary/obsidian"
    cd /home/yashindo/nix-config
    ${pkgs.python3}/bin/python "$vault_helper" manifest "$source" > "$temporary/start.manifest.sha256"
    ${pkgs.coreutils}/bin/printf '%s\n' \
      '{"nodes":[],"edges":[],"hyperedges":[],"input_tokens":0,"output_tokens":0}' \
      > "$temporary/graphify-out/graph.json"
    ${pkgs.python3}/bin/python "$vault_helper" build "$source" "$temporary/graphify-out/graph.json"
    ${pkgs.pipenv}/bin/pipenv run graphify export obsidian \
      --graph "$temporary/graphify-out/graph.json" \
      --dir "$temporary/obsidian"
    ${pkgs.python3}/bin/python "$vault_helper" manifest "$source" > "$temporary/manifest.sha256"
    if ! ${pkgs.diffutils}/bin/cmp -s "$temporary/start.manifest.sha256" "$temporary/manifest.sha256"; then
      echo "Hermes vault changed during Graphify build; preserving the previous generation." >&2
      exit 1
    fi

    if test -d "$state/graphify-out"; then
      ${pkgs.coreutils}/bin/mv "$state/graphify-out" "$old_graph"
      old_graph_moved=1
    fi
    if test -d "$derived"; then
      ${pkgs.coreutils}/bin/mv "$derived" "$old_derived"
      old_derived_moved=1
    fi
    ${pkgs.coreutils}/bin/mv "$temporary/graphify-out" "$state/graphify-out"
    new_graph_installed=1
    ${pkgs.coreutils}/bin/mv "$temporary/obsidian" "$derived"
    new_derived_installed=1
    ${pkgs.coreutils}/bin/mv "$temporary/manifest.sha256" "$manifest"
  '';
  graphifyWatcher = pkgs.writeShellScript "graphify-watch-hermes-vault" ''
    set -euo pipefail

    source=${lib.escapeShellArg vaultPath}
    event_args=(-r -e close_write,moved_to,moved_from,create,delete --format '%w%f')

    is_markdown() {
      case "$1" in
        *.md|*.MD) return 0 ;;
        *) return 1 ;;
      esac
    }

    while true; do
      pending=0
      event="$(${pkgs.inotify-tools}/bin/inotifywait "''${event_args[@]}" "$source")"
      if is_markdown "$event"; then
        pending=1
      fi
      while event="$(${pkgs.inotify-tools}/bin/inotifywait -t 15 "''${event_args[@]}" "$source" 2>/dev/null)"; do
        if is_markdown "$event"; then
          pending=1
        fi
      done
      if test "$pending" -eq 1; then
        ${graphifyBuild}
      fi
    done
  '';
  vaultMarkdownModeFixup = pkgs.writeShellScript "hermes-vault-markdown-mode-fixup" ''
    set -euo pipefail
    find=${pkgs.findutils}/bin/find
    chmod=${pkgs.coreutils}/bin/chmod
    vault=${lib.escapeShellArg vaultPath}
    "$find" "$vault" -type f -name '*.md' ! -perm 0660 -exec "$chmod" 0660 {} +
  '';
in {
  options.modules.graphify = {
    enable = lib.mkEnableOption "Graphify indexing and MCP server";
    port = lib.mkOption {
      type = lib.types.port;
      default = 9292;
      description = "Loopback port for the Graphify MCP server.";
    };
    notesPort = lib.mkOption {
      type = lib.types.port;
      default = 9293;
      description = "Loopback port for the Hermes notes MCP server.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.modules.obsidianHermesVault.enable;
        message = "modules.graphify.enable requires modules.obsidianHermesVault.enable.";
      }
    ];

    systemd.services.graphify-hermes-vault = {
      description = "Build the Hermes Obsidian knowledge graph";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "hermes-vault-markdown-mode-fixup.service"];
      wants = ["network-online.target" "hermes-vault-markdown-mode-fixup.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "yashindo";
        Group = "obsidian-hermes";
        ExecStart = graphifyBuild;
        WorkingDirectory = "/home/yashindo/nix-config";
        ReadWritePaths = ["/var/lib/graphify"];
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        UMask = "0007";
      };
    };

    systemd.services.hermes-vault-markdown-mode-fixup = {
      description = "Ensure Hermes vault Markdown files are group-readable (0660)";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "yashindo";
        Group = "obsidian-hermes";
        ExecStart = vaultMarkdownModeFixup;
        ReadWritePaths = [vaultPath];
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.services.graphify-hermes-vault-watcher = {
      description = "Watch the Hermes Obsidian vault for Graphify rebuilds";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.inotify-tools];
      serviceConfig = {
        User = "yashindo";
        Group = "obsidian-hermes";
        ExecStart = graphifyWatcher;
        WorkingDirectory = "/home/yashindo/nix-config";
        ReadWritePaths = ["/var/lib/graphify"];
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        Restart = "always";
        RestartSec = 2;
        UMask = "0007";
      };
    };

    systemd.timers.graphify-hermes-vault = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1h";
        Persistent = true;
        Unit = "graphify-hermes-vault.service";
      };
    };

    systemd.services.graphify-mcp = {
      description = "Graphify MCP server for the Hermes Obsidian vault";
      wantedBy = ["multi-user.target"];
      after = ["graphify-hermes-vault.service"];
      wants = ["graphify-hermes-vault.service"];
      serviceConfig = {
        User = "yashindo";
        Group = "obsidian-hermes";
        WorkingDirectory = "/home/yashindo/nix-config";
        ExecStart = "${pkgs.pipenv}/bin/pipenv run python -m graphify.serve --transport http --graph ${graphPath} --host 127.0.0.1 --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 5;
        ReadOnlyPaths = [statePath];
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.services.graphify-notes-mcp = {
      description = "Read-only notes MCP server for the Hermes Obsidian vault";
      wantedBy = ["multi-user.target"];
      after = ["hermes-vault-markdown-mode-fixup.service"];
      wants = ["hermes-vault-markdown-mode-fixup.service"];
      serviceConfig = {
        User = "yashindo";
        Group = "obsidian-hermes";
        WorkingDirectory = "/home/yashindo/nix-config";
        ExecStart = "${pkgs.pipenv}/bin/pipenv run python ${notesHelper} --vault ${vaultPath} --host 127.0.0.1 --port ${toString cfg.notesPort}";
        Restart = "on-failure";
        RestartSec = 5;
        ReadOnlyPaths = [vaultPath];
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}

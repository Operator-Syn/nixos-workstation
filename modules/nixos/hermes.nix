{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  hermes = inputs.hermes-agent.packages.${system}.default;
  agent-browser = pkgs.stdenv.mkDerivation {
    pname = "agent-browser";
    version = "0.32.1";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/agent-browser/-/agent-browser-0.32.1.tgz";
      hash = "sha256-NCS0BWq8exGch/6pDYyZs36rmRBNSjhQBgCTcXLoKdA=";
    };

    sourceRoot = ".";
    unpackPhase = ''
      tar xzf "$src"
    '';

    installPhase = ''
      install -Dm755 package/bin/agent-browser-linux-x64 "$out/bin/agent-browser"
    '';
  };

  hermes-auth-feilhann = pkgs.writeShellScriptBin "hermes-auth-feilhann" ''
    exec /run/wrappers/bin/sudo -u feilhann -H ${pkgs.coreutils}/bin/env \
      HOME=/home/feilhann \
      HERMES_HOME=/home/feilhann/.hermes \
      HERMES_MANAGED_DIR=/etc/hermes \
      HERMES_WRITE_SAFE_ROOT=/home/feilhann \
      ${hermes}/bin/hermes auth add openai-codex
  '';

  hermes-desktop-doctor = pkgs.writeShellScriptBin "hermes-desktop-doctor" ''
    set -euo pipefail

    token_file=/run/hermes/dashboard-token
    desktop_entry="$HOME/.local/share/applications/hermes-desktop.desktop"
    token="$(/run/wrappers/bin/sg hermes-desktop -c '${pkgs.coreutils}/bin/cut -d= -f2- /run/hermes/dashboard-token' 2>/dev/null || true)"
    backend_state="$(${pkgs.systemd}/bin/systemctl is-active hermes-desktop-backend.service 2>/dev/null || true)"
    backend_processes="$(${pkgs.procps}/bin/pgrep -af 'hermes serve' || true)"

    echo "Hermes backend: ''${backend_state:-inactive}"
    echo "Hermes listener:"
    ${pkgs.iproute2}/bin/ss -ltn 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E '127\.0\.0\.1:9119|State' || true

    if test -n "$token"; then
      echo "Dashboard token: readable through hermes-desktop group"
      unauthenticated="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9119/api/config || true)"
      authenticated="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $token" http://127.0.0.1:9119/api/config || true)"
      echo "Unauthenticated API status: $unauthenticated"
      echo "Token-authenticated API status: $authenticated"
    else
      echo "Dashboard token: unavailable"
    fi

    if test -e "$desktop_entry"; then
      echo "Desktop entry: $(readlink -f "$desktop_entry")"
    else
      echo "Desktop entry: missing ($desktop_entry)"
    fi

    echo "Hermes serve processes:"
    echo "''${backend_processes:-none}"
    if test -f "$HOME/.config/Hermes/connection.json" && ${pkgs.gnugrep}/bin/grep -q '"mode"[[:space:]]*:[[:space:]]*"local"' "$HOME/.config/Hermes/connection.json"; then
      echo "Desktop connection.json: local (wrapper environment must be used)"
    else
      echo "Desktop connection.json: not local or unavailable"
    fi

    echo "Home audit access:"
    audit_find="$(/run/wrappers/bin/sudo -u feilhann -H \
      ${pkgs.findutils}/bin/find /home/yashindo -maxdepth 1 -mindepth 1 -print -quit >/dev/null 2>&1 && echo yes || echo no)"
    audit_read="$(/run/wrappers/bin/sudo -u feilhann -H \
      ${pkgs.coreutils}/bin/test -r /home/yashindo/nix-config/flake.nix && echo yes || echo no)"
    audit_execute="$(/run/wrappers/bin/sudo -u feilhann -H \
      ${pkgs.coreutils}/bin/test -x /home/yashindo/nix-config && echo yes || echo no)"
    audit_write="$(/run/wrappers/bin/sudo -u feilhann -H \
      ${pkgs.coreutils}/bin/test -w /home/yashindo && echo yes || echo no)"
    echo "  traversal: $audit_find"
    echo "  representative read: $audit_read"
    echo "  executable directory access: $audit_execute"
    echo "  home write access: $audit_write"
    ${config.services.homeAcl.statusCommand}/bin/home-acl-status

    audit_report=/run/hermes-audit/report
    if test -r "$audit_report"; then
      echo "  privileged audit report: $audit_report"
      echo "  report timestamp: $(stat -c '%y' "$audit_report")"
      echo "  report ownership: $(stat -c '%U:%G %a' "$audit_report")"
      ${pkgs.gnugrep}/bin/grep -E '^(Collector status|Section .* status|Current system generation):' "$audit_report" || true
    else
      echo "  privileged audit report: unavailable"
    fi
  '';

  hermes-audit-report = pkgs.writeShellScript "hermes-audit-report" ''
    set -euo pipefail

    report_dir=/run/hermes-audit
    report=$report_dir/report
    temporary="''${report}.tmp.$$"
    section_temporary=""
    awk=${pkgs.gawk}/bin/awk
    ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g hermes-audit-readonly "$report_dir"

    cleanup_section_temporary() {
      if test -n "$section_temporary"; then
        ${pkgs.coreutils}/bin/rm -f "$section_temporary"
      fi
    }

    publish_failure() {
      status="$?"
      cleanup_section_temporary
      {
        echo "Generated UTC: $(${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Collector status: failed"
        echo "Collector failure exit status: $status"
      } > "$temporary"
      ${pkgs.coreutils}/bin/chown root:hermes-audit-readonly "$temporary"
      ${pkgs.coreutils}/bin/chmod 0640 "$temporary"
      ${pkgs.coreutils}/bin/mv -f "$temporary" "$report"
      exit "$status"
    }
    trap publish_failure ERR

    redact() {
      ${pkgs.gnused}/bin/sed -E \
        -e 's/((bearer|token|password|passwd|api[_-]?key)[=:][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
        -e '/-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----/,/-----END ([A-Z0-9 ]+ )?PRIVATE KEY-----/c\\[REDACTED PRIVATE KEY BLOCK]'
    }

    section() {
      title="$1"
      shift
      section_temporary="$(${pkgs.coreutils}/bin/mktemp "$report_dir/section.XXXXXX")"
      echo "== $title =="
      if ${pkgs.coreutils}/bin/timeout 15s "$@" 2>&1 | redact | LC_ALL=C "$awk" -v limit=65536 '
        {
          remaining = limit - written
          if (remaining <= 0) {
            next
          }

          line = $0 ORS
          if (length(line) > remaining) {
            printf "%s", substr(line, 1, remaining)
            written += remaining
          } else {
            printf "%s", line
            written += length(line)
          }
        }
      ' > "$section_temporary"; then
        echo "Section $title status: ok"
      else
        echo "Section $title status: failed"
        collector_failed=1
      fi
      ${pkgs.coreutils}/bin/cat "$section_temporary"
      cleanup_section_temporary
      section_temporary=""
      echo
    }

    collector_failed=0
    {
      echo "Generated UTC: $(${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "Host: $(${pkgs.coreutils}/bin/hostname)"
      echo "Current system generation: $(readlink -f /run/current-system 2>/dev/null || echo unavailable)"
      echo "Booted system generation: $(readlink -f /run/booted-system 2>/dev/null || echo unavailable)"
      echo "System profile: $(readlink -f /nix/var/nix/profiles/system 2>/dev/null || echo unavailable)"
      echo "Configuration provenance: /home/yashindo/nix-config#nixos (hosts/hiraeth)"
      echo "Collector status: running"
      echo "Hermes ACL service: $(${pkgs.systemd}/bin/systemctl is-active hermes-home-audit-acl.service 2>/dev/null || true)"
      echo "Hermes backend: $(${pkgs.systemd}/bin/systemctl is-active hermes-desktop-backend.service 2>/dev/null || true)"
      section "Hermes journal" ${pkgs.systemd}/bin/journalctl --no-pager --output=short-iso -b \
        -u hermes-home-audit-acl.service -u hermes-audit-report.service -u hermes-desktop-backend.service -n 160
      section "System journal summary" ${pkgs.systemd}/bin/journalctl --no-pager --output=short-iso -b -p warning..emerg -n 160
      section "Authentication summary" ${pkgs.bash}/bin/bash -c \
        "${pkgs.systemd}/bin/journalctl --no-pager --output=short-iso -b -n 240 | ${pkgs.gnugrep}/bin/grep -Ei 'sshd|sudo|polkit|session|authentication|failed password|accepted password'"
      section "Failed systemd units" ${pkgs.systemd}/bin/systemctl --failed --no-legend --no-pager
      section "Firewall ruleset" ${pkgs.nftables}/bin/nft list ruleset
      section "Recent NixOS generations" ${pkgs.bash}/bin/bash -c \
        "${pkgs.findutils}/bin/find /nix/var/nix/profiles -maxdepth 1 -type l -name 'system-*-link' -printf '%f -> %l\\n' 2>/dev/null | ${pkgs.coreutils}/bin/sort -V | ${pkgs.coreutils}/bin/tail -20"
      if test "$collector_failed" -eq 0; then
        echo "Collector final status: ok"
      else
        echo "Collector final status: failed"
      fi
    } > "$temporary"

    ${pkgs.coreutils}/bin/chown root:hermes-audit-readonly "$temporary"
    ${pkgs.coreutils}/bin/chmod 0640 "$temporary"
    ${pkgs.coreutils}/bin/mv -f "$temporary" "$report"
  '';
in
{
  environment.systemPackages = [
    hermes-auth-feilhann
    hermes-desktop-doctor
  ];

  systemd.services.hermes-audit-report = {
    description = "Generate scoped Hermes system audit report";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = hermes-audit-report;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/run/hermes-audit" ];
      Group = "hermes-audit-readonly";
      RuntimeDirectory = "hermes-audit";
      RuntimeDirectoryMode = "0750";
      RuntimeDirectoryPreserve = "yes";
      TimeoutStartSec = "2min";
      UMask = "0027";
    };
  };

  systemd.timers.hermes-audit-report = {
    description = "Refresh scoped Hermes system audit report";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
      Unit = "hermes-audit-report.service";
    };
  };

  systemd.services.hermes-dashboard-token = {
    description = "Hermes Desktop loopback session token";
    wantedBy = [ "multi-user.target" ];
    before = [ "hermes-desktop-backend.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "hermes-dashboard-token-init" ''
        set -eu
        token_file=/run/hermes/dashboard-token
        ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g hermes-desktop /run/hermes

        if ! test -s "$token_file"; then
          tmp_file="''${token_file}.tmp.$$"
          token="$(${pkgs.coreutils}/bin/head -c 48 /dev/urandom | ${pkgs.coreutils}/bin/base64 -w0)"
          printf 'HERMES_DASHBOARD_SESSION_TOKEN=%s\n' "$token" > "$tmp_file"
          ${pkgs.coreutils}/bin/chown root:hermes-desktop "$tmp_file"
          ${pkgs.coreutils}/bin/chmod 0640 "$tmp_file"
          ${pkgs.coreutils}/bin/mv "$tmp_file" "$token_file"
        fi
      '';
    };
  };

  environment.etc."hermes/config.yaml".text = builtins.toJSON {
    model.provider = "openai-codex";

    toolsets = [
      "terminal"
      "file"
      "web"
      "browser"
      "memory"
      "session_search"
      "cronjob"
      "todo"
      "clarify"
    ];

    terminal = {
      backend = "local";
      cwd = "/home/feilhann";
      timeout = 180;
    };

    web.backend = "ddgs";

    approvals = {
      mode = "smart";
      cron_mode = "deny";
    };
  };

  systemd.tmpfiles.rules = [
    "d /home/feilhann/.hermes 0700 feilhann feilhann - -"
    "d /home/feilhann/.hermes/browser-profile 0700 feilhann feilhann - -"
  ];

  systemd.services.hermes-desktop-backend = {
    description = "Hermes Desktop backend";
    wantedBy = [ "multi-user.target" ];
    after = [
      "hermes-dashboard-token.service"
      "network-online.target"
    ];
    requires = [ "hermes-dashboard-token.service" ];
    wants = [
      "hermes-dashboard-token.service"
      "network-online.target"
    ];

    environment = {
      HOME = "/home/feilhann";
      HERMES_HOME = "/home/feilhann/.hermes";
      HERMES_MANAGED_DIR = "/etc/hermes";
      HERMES_WRITE_SAFE_ROOT = "/home/feilhann";
      AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      AGENT_BROWSER_PROFILE = "/home/feilhann/.hermes/browser-profile";
      AGENT_BROWSER_DOWNLOAD_PATH = "/home/feilhann/Downloads";
    };

    serviceConfig = {
      User = "feilhann";
      Group = "feilhann";
      SupplementaryGroups = [ "hermes-desktop" ];
      WorkingDirectory = "/home/feilhann";
      EnvironmentFile = "/run/hermes/dashboard-token";
      ExecStartPre = "${pkgs.coreutils}/bin/test -s /run/hermes/dashboard-token";
      ExecStart = "${hermes}/bin/hermes serve --host 127.0.0.1 --port 9119 --no-open";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "/home/feilhann" ];
      ProtectControlGroups = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
    };

    path = [
      hermes
      agent-browser
      pkgs.bash
      pkgs.chromium
      pkgs.coreutils
      pkgs.git
      pkgs.findutils
      pkgs.ripgrep
    ];
  };
}

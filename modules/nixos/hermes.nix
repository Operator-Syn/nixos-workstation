{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  cfg = config.modules.hermes;
  username = "yashindo";
  homeDirectory = "/home/yashindo";
  hermesHome = "${homeDirectory}/.hermes";
  vaultPath = "/srv/obsidian/hermes-vault";
  graphifyEnabled = lib.attrByPath ["modules" "hermes" "graphify" "enable"] false config;
  hermes = inputs.hermes-agent.packages.${system}.default;
  pythonWithDdgs = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.ddgs
  ]);
  ddgsPythonPath = lib.makeSearchPath pkgs.python312.sitePackages [
    pkgs.python312Packages.ddgs
    pkgs.python312Packages.lxml
    pkgs.python312Packages.brotli
  ];
  hermesPlugins = pkgs.runCommand "hermes-plugins" {} ''
    cp -r ${hermes}/share/hermes-agent/plugins "$out"
    substituteInPlace "$out/web/ddgs/provider.py" \
      --replace-fail \
        'client.text(query, max_results=safe_limit)' \
        'client.text(query, max_results=safe_limit, backend="google,startpage")'
  '';
  hermesWeb = pkgs.writeShellScriptBin "hermes-web" ''
    export HERMES_BUNDLED_SKILLS=${hermes}/share/hermes-agent/skills
    export HERMES_BUNDLED_PLUGINS=${hermesPlugins}
    export HERMES_BUNDLED_LOCALES=${hermes}/share/hermes-agent/locales
    export HERMES_WEB_DIST=${hermes}/share/hermes-agent/web_dist
    export HERMES_TUI_DIR=${hermes}/ui-tui
    export HERMES_PYTHON=${hermes.passthru.hermesVenv}/bin/python3
    export HERMES_NODE=${lib.getExe pkgs.nodejs}

    exec ${hermes.passthru.hermesVenv}/bin/hermes "$@"
  '';
  agentBrowser = pkgs.stdenv.mkDerivation {
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
  hermesCli = pkgs.writeShellScriptBin "hermes" ''
    set -eu

    export HOME=${homeDirectory}
    export HERMES_HOME=${hermesHome}
    export HERMES_WRITE_SAFE_ROOT=${homeDirectory}:/srv/obsidian/hermes-vault:/var/lib/graphify/hermes-derived-vault
    export HERMES_BUNDLED_SKILLS=${hermes}/share/hermes-agent/skills
    export HERMES_BUNDLED_PLUGINS=${hermesPlugins}
    export HERMES_BUNDLED_LOCALES=${hermes}/share/hermes-agent/locales
    export HERMES_WEB_DIST=${hermes}/share/hermes-agent/web_dist
    export HERMES_TUI_DIR=${hermes}/ui-tui
    export HERMES_PYTHON=${hermes.passthru.hermesVenv}/bin/python3
    export HERMES_NODE=${lib.getExe pkgs.nodejs}

    exec ${hermes}/bin/hermes "$@"
  '';
  hermesDesktopDoctor = pkgs.writeShellScriptBin "hermes-desktop-doctor" ''
    set -euo pipefail

    token_file=/run/hermes/dashboard-token
    desktop_entry="$HOME/.local/share/applications/hermes-desktop.desktop"
    token="$(${pkgs.coreutils}/bin/cut -d= -f2- "$token_file" 2>/dev/null || true)"
    backend_state="$(${pkgs.systemd}/bin/systemctl is-active hermes-desktop-backend.service 2>/dev/null || true)"

    echo "Hermes backend container: ''${backend_state:-inactive}"
    echo "Hermes listener:"
    ${pkgs.iproute2}/bin/ss -ltn 2>/dev/null | ${pkgs.gnugrep}/bin/grep -E '127\\.0\\.0\\.1:9119|State' || true

    if test -n "$token"; then
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

    echo "Hermes state: ${hermesHome}"
    echo "Hermes config: ${hermesHome}/config.yaml"
  '';
  ghWrapper = name: tokenPath: pkgs.writeShellScriptBin name ''
    set -eu

    export GH_TOKEN="$(${pkgs.coreutils}/bin/cat ${tokenPath})"
    export GH_CONFIG_DIR="${hermesHome}/gh-config-${name}"
    ${pkgs.coreutils}/bin/mkdir -p "$GH_CONFIG_DIR"

    exec ${pkgs.gh}/bin/gh "$@"
  '';
  ghFeilhann = ghWrapper "gh-feilhann" "/run/hermes/gh/feilhann.token";
  ghOperatorSyn = ghWrapper "gh-operator-syn" "/run/hermes/gh/operator-syn.token";
  hermesRuntimeDirs = pkgs.runCommand "hermes-backend-runtime-dirs" {} ''
    mkdir -p "$out/run/hermes/gh"
  '';
  hermesContainerNss = pkgs.runCommand "hermes-backend-nss" {} ''
    mkdir -p "$out/etc" "$out/var/empty"
    cat > "$out/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/sh
yashindo:x:${toString config.users.users.${username}.uid}:${toString config.users.groups.users.gid}:Yashindo:${homeDirectory}:/bin/bash
nobody:x:65534:65534:nobody:/var/empty:/bin/sh
EOF
    cat > "$out/etc/group" <<EOF
root:x:0:
users:x:${toString config.users.groups.users.gid}:
nobody:x:65534:
EOF
    cat > "$out/etc/nsswitch.conf" <<EOF
passwd: files
group: files
shadow: files
hosts: files dns
EOF
  '';
  hermesBackendImage = pkgs.dockerTools.buildLayeredImage {
    name = "hermes-backend";
    tag = "latest";
    contents = [
      hermesRuntimeDirs
      hermesContainerNss
      hermesWeb
      agentBrowser
      pythonWithDdgs
      pkgs.python3
      pkgs.pipenv
      pkgs.openssh
      pkgs.bun
      pkgs.bash
      pkgs.cacert
      pkgs.chromium
      pkgs.coreutils
      pkgs.curl
      pkgs.diffutils
      pkgs.file
      ghFeilhann
      pkgs.findutils
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
      pkgs.gnutar
      pkgs.git
      pkgs.gh
      pkgs.gzip
      pkgs.jq
      pkgs.less
      pkgs.alejandra
      pkgs.nix
      pkgs.nodejs
      pkgs.openssl
      pkgs.patch
      pkgs.procps
      ghOperatorSyn
      pkgs.ripgrep
      pkgs.lsof
      pkgs.sqlite
      pkgs.util-linux
      pkgs.unzip
      pkgs.which
      pkgs.wget
    ];
    config = {
      User = "${toString config.users.users.${username}.uid}:${toString config.users.groups.users.gid}";
      WorkingDir = homeDirectory;
      Env = [
        "HOME=${homeDirectory}"
        "HERMES_HOME=${hermesHome}"
        "HERMES_WRITE_SAFE_ROOT=${homeDirectory}:/srv/obsidian/hermes-vault:/var/lib/graphify/hermes-derived-vault"
        "PYTHONPATH=${ddgsPythonPath}"
        "AGENT_BROWSER_EXECUTABLE_PATH=/bin/chromium"
        "AGENT_BROWSER_PROFILE=${hermesHome}/browser-profile"
        "AGENT_BROWSER_DOWNLOAD_PATH=${homeDirectory}/Downloads"
        "OBSIDIAN_VAULT_PATH=${vaultPath}"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt"
      ];
      Cmd = [
        "${hermesWeb}/bin/hermes-web"
        "serve"
        "--host"
        "127.0.0.1"
        "--port"
        "9119"
        "--no-open"
      ];
    };
  };
in {
  options.modules.hermes.enable = lib.mkEnableOption "Hermes Agent backend";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.users.users.${username}.uid != null;
        message = "The Hermes backend container requires an explicit Yashindo UID.";
      }
    ];

    virtualisation.oci-containers.backend = "docker";

    users.groups.hermes-desktop = {
      members = [username];
    };

    environment.systemPackages = [
      hermesCli
      hermesDesktopDoctor
      pythonWithDdgs
    ];

    systemd.services.hermes-dashboard-token = {
      description = "Hermes Desktop loopback session token";
      wantedBy = ["multi-user.target"];
      before = ["hermes-desktop-backend.service"];

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

    systemd.tmpfiles.rules = [
      "d /run/hermes/gh 0700 ${username} users - -"
      "d ${hermesHome} 0700 ${username} users - -"
      "d ${hermesHome}/browser-profile 0700 ${username} users - -"
    ];

    virtualisation.oci-containers.containers.hermes-backend = {
      image = "hermes-backend:latest";
      imageFile = hermesBackendImage;
      serviceName = "hermes-desktop-backend";
      autoStart = true;
      user = "${toString config.users.users.${username}.uid}:${toString config.users.groups.users.gid}";
      workdir = homeDirectory;
      environmentFiles = ["/run/hermes/dashboard-token"];
      volumes =
        [
          "${homeDirectory}:${homeDirectory}:rw"
          "/run/secrets/gh_token:/run/hermes/gh/feilhann.token:ro"
          "/run/secrets/gh_operator_syn_token:/run/hermes/gh/operator-syn.token:ro"
          "/run/hermes/gh:${homeDirectory}/.config/gh:ro"
        ]
        ++ lib.optional graphifyEnabled "${vaultPath}:${vaultPath}:rw";
      extraOptions = ["--network=host"];
    };

    systemd.services.hermes-desktop-backend = {
      after = ["hermes-dashboard-token.service" "network-online.target"];
      requires = ["hermes-dashboard-token.service"];
      wants = ["network-online.target"];
    };
  };
}

{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  desktop = inputs.hermes-agent.packages.${system}.desktop;
  desktop-launcher = pkgs.writeShellScriptBin "hermes-desktop-launcher" ''
    set -eu
    if ! token="$(/run/wrappers/bin/sg hermes-desktop -c '${pkgs.coreutils}/bin/cut -d= -f2- /run/hermes/dashboard-token')" || test -z "$token"; then
      echo "Hermes dashboard token is unavailable; verify the hermes-dashboard-token.service is active." >&2
      exit 1
    fi

    export HERMES_DESKTOP_REMOTE_URL=http://127.0.0.1:9119
    export HERMES_DESKTOP_REMOTE_TOKEN="$token"
    exec ${desktop}/bin/hermes-desktop "$@"
  '';
in {
  options.modules.hermes-desktop.enable = lib.mkEnableOption "Hermes Desktop";

  config = lib.mkIf config.modules.hermes-desktop.enable {
    home.packages = [
      desktop-launcher
    ];

    home.file.".local/share/applications/hermes-desktop.desktop".text = ''
      [Desktop Entry]
      Name=Hermes Desktop
      Comment=Desktop interface for the Hermes agent
      Exec=${desktop-launcher}/bin/hermes-desktop-launcher %U
      TryExec=${desktop-launcher}/bin/hermes-desktop-launcher
      Icon=org.supertux.SuperTux-Milestone1
      Terminal=false
      Type=Application
      Categories=Development;Utility;
      StartupWMClass=Hermes
    '';
  };
}

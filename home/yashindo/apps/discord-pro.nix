# discord-pro.nix
{
  pkgs,
  lib,
  config,
  ...
}: let
  proBase = "${config.home.homeDirectory}/.local/share/discord-pro";

  discord-pro = pkgs.writeShellScriptBin "discord-pro" ''
    set -eu

    REAL_XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

    PRO_BASE="${proBase}"
    PRO_RUNTIME="$PRO_BASE/runtime"
    PRO_CONFIG="$PRO_BASE/config"
    PRO_CACHE="$PRO_BASE/cache"
    PRO_DATA="$PRO_BASE/data"

    mkdir -p "$PRO_RUNTIME" "$PRO_CONFIG" "$PRO_CACHE" "$PRO_DATA"
    chmod 700 "$PRO_RUNTIME"

    # Bridge PulseAudio / PipeWire-Pulse socket.
    if [ -S "$REAL_XDG_RUNTIME_DIR/pulse/native" ]; then
      mkdir -p "$PRO_RUNTIME/pulse"
      ln -sfn "$REAL_XDG_RUNTIME_DIR/pulse/native" "$PRO_RUNTIME/pulse/native"

      # Use the real Pulse socket directly.
      export PULSE_SERVER="unix:$REAL_XDG_RUNTIME_DIR/pulse/native"
    fi

    # Bridge PipeWire socket.
    if [ -S "$REAL_XDG_RUNTIME_DIR/pipewire-0" ]; then
      ln -sfn "$REAL_XDG_RUNTIME_DIR/pipewire-0" "$PRO_RUNTIME/pipewire-0"
    fi

    # Some systems also expose this PipeWire manager socket.
    if [ -S "$REAL_XDG_RUNTIME_DIR/pipewire-0-manager" ]; then
      ln -sfn "$REAL_XDG_RUNTIME_DIR/pipewire-0-manager" "$PRO_RUNTIME/pipewire-0-manager"
    fi

    # Bridge session bus.
    if [ -S "$REAL_XDG_RUNTIME_DIR/bus" ]; then
      ln -sfn "$REAL_XDG_RUNTIME_DIR/bus" "$PRO_RUNTIME/bus"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$REAL_XDG_RUNTIME_DIR/bus"
    fi

    # Bridge Wayland socket if running under Wayland.
    if [ -n "''${WAYLAND_DISPLAY:-}" ] && [ -S "$REAL_XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
      ln -sfn "$REAL_XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$PRO_RUNTIME/$WAYLAND_DISPLAY"
    fi

    # Bridge Pulse cookie because XDG_CONFIG_HOME is isolated below.
    # Without this, audio output may appear while mic capture behaves strangely.
    if [ -f "$HOME/.config/pulse/cookie" ]; then
      mkdir -p "$PRO_CONFIG/pulse"
      ln -sfn "$HOME/.config/pulse/cookie" "$PRO_CONFIG/pulse/cookie"
      export PULSE_COOKIE="$HOME/.config/pulse/cookie"
    fi

    export XDG_RUNTIME_DIR="$PRO_RUNTIME"
    export XDG_CONFIG_HOME="$PRO_CONFIG"
    export XDG_CACHE_HOME="$PRO_CACHE"
    export XDG_DATA_HOME="$PRO_DATA"

    exec nvidia-offload ${pkgs.discord}/bin/discord "$@"
  '';

  discord-pro-login-prompt = pkgs.writeShellScriptBin "discord-pro-login-prompt" ''
    if ${lib.getExe pkgs.kdePackages.kdialog} \
      --title "Start Discord Professional?" \
      --yesno "Would you like Discord Professional to run in the background now?"; then
      exec ${lib.getExe discord-pro} --start-minimized
    fi
  '';
in {
  options.modules.discord-pro.enable =
    lib.mkEnableOption "Secondary Professional Discord";

  config = lib.mkIf config.modules.discord-pro.enable {
    home.packages = [
      discord-pro
      pkgs.kdePackages.kdialog
      discord-pro-login-prompt
    ];

    home.file.".local/share/discord-pro/config/discord/settings.json".text = builtins.toJSON {
      SKIP_HOST_UPDATE = true;
    };

    home.file.".local/share/applications/discord-pro.desktop".text = ''
      [Desktop Entry]
      Name=Discord Professional
      Exec=${lib.getExe discord-pro} --start-minimized
      Icon=discord
      Type=Application
      Categories=Network;InstantMessaging;
    '';

    xdg.configFile."autostart/discord-pro.desktop".text = ''
      [Desktop Entry]
      Name=Discord Professional
      Exec=${lib.getExe discord-pro-login-prompt}
      Type=Application
      Categories=Network;InstantMessaging;
    '';
  };
}

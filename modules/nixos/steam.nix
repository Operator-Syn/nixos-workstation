# modules/nixos/steam.nix
{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}: let
  gamemodeKwinAnimations = pkgs.writeShellScriptBin "gamemode-kwin-animations" ''
    set -eu

    action="''${1:-}"
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    state_file="$runtime_dir/gamemode-kwin-animations.state"
    kreadconfig="${pkgs.kdePackages.kconfig}/bin/kreadconfig6"
    kwriteconfig="${pkgs.kdePackages.kconfig}/bin/kwriteconfig6"
    qdbus="${pkgs.qt6Packages.qttools}/bin/qdbus"

    reconfigure_kwin() {
      DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime_dir/bus}" \
        "$qdbus" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    }

    suppress_animations() {
      if [ -e "$state_file" ]; then
        return 0
      fi

      "${pkgs.coreutils}/bin/mkdir" -p "$runtime_dir"
      current_factor="$("$kreadconfig" --file kdeglobals --group KDE --key AnimationDurationFactor --default __unset__)"
      previous_umask=$(umask)
      umask 077
      printf '%s\n' "$current_factor" > "$state_file"
      umask "$previous_umask"
      "$kwriteconfig" --file kdeglobals --group KDE --key AnimationDurationFactor 0 --notify
      reconfigure_kwin
    }

    restore_animations() {
      if [ ! -e "$state_file" ]; then
        return 0
      fi

      current_factor="$(${pkgs.coreutils}/bin/cat "$state_file")"
      if [ "$current_factor" = __unset__ ]; then
        "$kwriteconfig" --file kdeglobals --group KDE --key AnimationDurationFactor --delete --notify
      else
        "$kwriteconfig" --file kdeglobals --group KDE --key AnimationDurationFactor "$current_factor" --notify
      fi
      reconfigure_kwin
      "${pkgs.coreutils}/bin/rm" -f "$state_file"
    }

    case "$action" in
      start)
        suppress_animations
        ;;
      end)
        restore_animations
        ;;
      *)
        printf '%s\n' 'Usage: gamemode-kwin-animations [start|end]' >&2
        exit 2
        ;;
    esac
  '';
in {
  imports = [
    ./steam/protontricks.nix
  ];

  options.modules.steam.enable =
    lib.mkEnableOption "Steam gaming support";

  config = lib.mkIf config.modules.steam.enable {
    modules.steam.protontricks.enable = lib.mkDefault true;

    programs.anime-game-launcher.enable = false;
    programs.honkers-railway-launcher.enable = false;

    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;

      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;

      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };

    programs.gamescope = {
      enable = true;
      capSysNice = true;
    };

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    hardware.steam-hardware.enable = true;

    programs.gamemode = {
      enable = true;
      settings.custom = {
        start = "${gamemodeKwinAnimations}/bin/gamemode-kwin-animations start";
        end = "${gamemodeKwinAnimations}/bin/gamemode-kwin-animations end";
      };
    };

    systemd.user.services.gamemode-manual = {
      description = "Manual GameMode override";
      after = ["gamemoded.service"];
      wants = ["gamemoded.service"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.gamemode}/bin/gamemoded -r";
        KillSignal = "SIGINT";
        TimeoutStopSec = 5;
      };
    };

    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "gamemode-toggle" ''
        set -eu

        unit="gamemode-manual.service"
        systemctl_user="${pkgs.systemd}/bin/systemctl"
        gamemoded="${pkgs.gamemode}/bin/gamemoded"

        print_status() {
          manual_state="$("$systemctl_user" --user is-active "$unit" 2>/dev/null || true)"
          printf 'Manual GameMode request: %s\n' "$manual_state"
          "$gamemoded" -s
        }

        case "''${1:-toggle}" in
          on | enable | start)
            "$systemctl_user" --user start "$unit"
            ;;
          off | disable | stop)
            "$systemctl_user" --user stop "$unit"
            ;;
          toggle)
            if "$systemctl_user" --user is-active --quiet "$unit"; then
              "$systemctl_user" --user stop "$unit"
            else
              "$systemctl_user" --user start "$unit"
            fi
            ;;
          status)
            print_status
            exit 0
            ;;
          -h | --help | help)
            printf '%s\n' 'Usage: gamemode-toggle [on|off|toggle|status]'
            exit 0
            ;;
          *)
            printf '%s\n' 'Usage: gamemode-toggle [on|off|toggle|status]' >&2
            exit 2
            ;;
        esac

        print_status
      '')
      lutris
      mangohud
      protonup-qt
      wineWow64Packages.waylandFull
      winetricks
      cabextract
      p7zip

      # The launchers declared above are disabled, so neither wrapper is
      # installed. Uncomment both entries to restore the commands.
      # (writeShellScriptBin "genshin-launcher" ''
      #   exec nvidia-offload ${anime-game-launcher}/bin/anime-game-launcher "$@"
      # '')
      #
      # (writeShellScriptBin "hsr-launcher" ''
      #   exec nvidia-offload ${honkers-railway-launcher}/bin/honkers-railway-launcher "$@"
      # '')
    ];
  };
}

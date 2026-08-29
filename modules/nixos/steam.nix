# modules/nixos/steam.nix
{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}: {
  imports = [
    ./steam/protontricks.nix
  ];

  options.modules.steam.enable =
    lib.mkEnableOption "Steam gaming support";

  config = lib.mkIf config.modules.steam.enable {
    modules.steam.protontricks.enable = lib.mkDefault true;

    programs.anime-game-launcher.enable = true;
    programs.honkers-railway-launcher.enable = true;

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

    programs.gamemode.enable = true;

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
      wineWowPackages.waylandFull
      winetricks
      cabextract
      p7zip

      (writeShellScriptBin "genshin-launcher" ''
        exec nvidia-offload ${anime-game-launcher}/bin/anime-game-launcher "$@"
      '')

      (writeShellScriptBin "hsr-launcher" ''
        exec nvidia-offload ${honkers-railway-launcher}/bin/honkers-railway-launcher "$@"
      '')
    ];
  };
}

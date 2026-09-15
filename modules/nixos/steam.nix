# modules/nixos/steam.nix
{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}: let
  kwinAnimationGuard = pkgs.writeShellScriptBin "kwin-animation-guard" ''
    set -eu

    action="''${1:-}"
    reason="''${2:-}"
    runtime_dir="''${GAMEMODE_RUNTIME_DIR:-''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}}"
    state_file="$runtime_dir/gamemode-kwin-animations.state"
    reason_dir="$runtime_dir/gamemode-kwin-animations.reasons"
    lock_file="$runtime_dir/gamemode-kwin-animations.lock"
    mkdir="${pkgs.coreutils}/bin/mkdir"
    cat="${pkgs.coreutils}/bin/cat"
    rm="${pkgs.coreutils}/bin/rm"
    rmdir="${pkgs.coreutils}/bin/rmdir"
    flock="${pkgs.util-linux}/bin/flock"
    kreadconfig="${pkgs.kdePackages.kconfig}/bin/kreadconfig6"
    kwriteconfig="${pkgs.kdePackages.kconfig}/bin/kwriteconfig6"
    qdbus="${pkgs.qt6Packages.qttools}/bin/qdbus"

    case "$reason" in
      gamemode | memory) ;;
      *)
        printf '%s\n' 'Usage: kwin-animation-guard [acquire|release] [gamemode|memory]' >&2
        exit 2
        ;;
    esac

    reason_marker="$reason_dir/$reason"

    reconfigure_kwin() {
      DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime_dir/bus}" \
        "$qdbus" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    }

    acquire_animations() {
      "$mkdir" -p "$runtime_dir" "$reason_dir"
      (
        "$flock" 9

        if [ -e "$reason_marker" ]; then
          exit 0
        fi

        if [ ! -e "$state_file" ]; then
          current_factor="$("$kreadconfig" --file kdeglobals --group KDE --key AnimationDurationFactor --default __unset__)"
          previous_umask=$(umask)
          umask 077
          printf '%s\n' "$current_factor" > "$state_file"
          umask "$previous_umask"
        fi

        "$kwriteconfig" --file kdeglobals --group KDE --key AnimationDurationFactor 0 --notify
        reconfigure_kwin

        previous_umask=$(umask)
        umask 077
        : > "$reason_marker"
        umask "$previous_umask"
      ) 9>"$lock_file"
    }

    release_animations() {
      if [ ! -e "$reason_marker" ] && [ ! -e "$state_file" ]; then
        return 0
      fi

      "$mkdir" -p "$runtime_dir" "$reason_dir"
      (
        "$flock" 9
        "$rm" -f "$reason_marker"

        if [ -e "$reason_dir/gamemode" ] || [ -e "$reason_dir/memory" ]; then
          exit 0
        fi

        if [ ! -e "$state_file" ]; then
          exit 0
        fi

        previous_factor="$("$cat" "$state_file")"
        if [ "$previous_factor" = __unset__ ]; then
          "$kwriteconfig" --file kdeglobals --group KDE --key AnimationDurationFactor --delete --notify
        else
          "$kwriteconfig" --file kdeglobals --group KDE --key AnimationDurationFactor "$previous_factor" --notify
        fi
        reconfigure_kwin
        "$rm" -f "$state_file"
        "$rmdir" "$reason_dir" 2>/dev/null || true
      ) 9>"$lock_file"
    }

    case "$action" in
      acquire)
        acquire_animations
        ;;
      release)
        release_animations
        ;;
      *)
        printf '%s\n' 'Usage: kwin-animation-guard [acquire|release] [gamemode|memory]' >&2
        exit 2
        ;;
    esac
  '';

  gamemodeKwinAnimations = pkgs.writeShellScriptBin "gamemode-kwin-animations" ''
    set -eu

    action="''${1:-}"
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    docker_state_file="$runtime_dir/gamemode-docker-containers.state"
    docker="${pkgs.docker_29}/bin/docker"
    kwin_animation_guard="${kwinAnimationGuard}/bin/kwin-animation-guard"

    stop_docker_containers() {
      if [ -e "$docker_state_file" ]; then
        return 0
      fi

      if ! running_containers="$("$docker" ps --quiet 2>/dev/null)"; then
        return 0
      fi
      if [ -z "$running_containers" ]; then
        return 0
      fi

      ${pkgs.coreutils}/bin/mkdir -p "$runtime_dir"
      previous_umask=$(umask)
      umask 077
      printf '%s\n' "$running_containers" > "$docker_state_file"
      umask "$previous_umask"

      while IFS= read -r container; do
        [ -n "$container" ] || continue
        "$docker" stop --time 5 "$container" >/dev/null 2>&1 || true
      done < "$docker_state_file"
    }

    start_docker_containers() {
      if [ ! -e "$docker_state_file" ]; then
        return 0
      fi

      while IFS= read -r container; do
        [ -n "$container" ] || continue
        "$docker" start "$container" >/dev/null 2>&1 || true
      done < "$docker_state_file"
      ${pkgs.coreutils}/bin/rm -f "$docker_state_file"
    }

    case "$action" in
      start)
        "$kwin_animation_guard" acquire gamemode
        stop_docker_containers
        ;;
      end)
        "$kwin_animation_guard" release gamemode
        start_docker_containers
        ;;
      *)
        printf '%s\n' 'Usage: gamemode-kwin-animations [start|end]' >&2
        exit 2
        ;;
    esac
  '';

  memoryAnimationGuard = pkgs.writeShellScriptBin "memory-animation-guard" ''
        set -eu

        meminfo_file="''${MEMORY_GUARD_MEMINFO_PATH:-/proc/meminfo}"
        poll_seconds="''${MEMORY_GUARD_POLL_SECONDS:-5}"
        max_samples="''${MEMORY_GUARD_MAX_SAMPLES:-0}"
        dry_run="''${MEMORY_GUARD_DRY_RUN:-0}"
        animation_guard="${kwinAnimationGuard}/bin/kwin-animation-guard"
        sleep="${pkgs.coreutils}/bin/sleep"
        awk="${pkgs.gawk}/bin/awk"

        enter_limit_percent=15
        exit_limit_percent=25
        enter_samples=6
        exit_samples=12
        low_samples=0
        high_samples=0
        sample_count=0
        guard_active=false

        case "$poll_seconds" in
          *[!0-9]*) poll_seconds=5 ;;
        esac
        if [ -z "$poll_seconds" ]; then
          poll_seconds=5
        fi
        case "$max_samples" in
          *[!0-9]*) max_samples=0 ;;
        esac
        if [ -z "$max_samples" ]; then
          max_samples=0
        fi

        read_meminfo() {
          "$awk" '
            $1 == "MemTotal:" { total = $2 }
            $1 == "MemAvailable:" { available = $2 }
            END {
              if (total ~ /^[0-9]+$/ && available ~ /^[0-9]+$/ && total > 0 && available >= 0) {
                print total, available
              }
            }
          ' "$meminfo_file"
        }

        request_acquire() {
          if [ "$dry_run" = 1 ]; then
            printf '%s\n' 'memory-animation-guard: dry-run acquire'
          else
            "$animation_guard" acquire memory
          fi
        }

        request_release() {
          if [ "$dry_run" = 1 ]; then
            printf '%s\n' 'memory-animation-guard: dry-run release'
          else
            "$animation_guard" release memory
          fi
        }

        cleanup() {
          if [ "$guard_active" = true ]; then
            request_release || true
          fi
        }

        trap cleanup EXIT
        trap 'exit 0' INT TERM

        if [ "$dry_run" != 1 ]; then
          "$animation_guard" release memory || true
        fi

        while :; do
          "$sleep" "$poll_seconds"
          sample_count=$((sample_count + 1))
          metrics="$(read_meminfo 2>/dev/null || true)"

          if [ -z "$metrics" ]; then
            printf '%s\n' 'memory-animation-guard: unable to read valid MemAvailable; leaving animations unchanged' >&2
            low_samples=0
            high_samples=0
          else
            total=0
            available=0
            IFS=' ' read -r total available <<EOF
    $metrics
    EOF

            if [ "$available" -le $((total * enter_limit_percent / 100)) ]; then
              low_samples=$((low_samples + 1))
              high_samples=0
            elif [ "$available" -ge $((total * exit_limit_percent / 100)) ]; then
              high_samples=$((high_samples + 1))
              low_samples=0
            else
              low_samples=0
              high_samples=0
            fi

            if [ "$guard_active" = false ] && [ "$low_samples" -ge "$enter_samples" ]; then
              guard_active=true
              if request_acquire; then
                printf 'memory-animation-guard: MemAvailable stayed at or below 15%% for 30 seconds; Plasma animations suppressed\n'
              else
                guard_active=false
                low_samples=0
                printf '%s\n' 'memory-animation-guard: failed to suppress Plasma animations; will retry' >&2
              fi
            elif [ "$guard_active" = true ] && [ "$high_samples" -ge "$exit_samples" ]; then
              if request_release; then
                guard_active=false
                printf 'memory-animation-guard: MemAvailable stayed at or above 25%% for 60 seconds; Plasma animations restored\n'
              else
                high_samples=0
                printf '%s\n' 'memory-animation-guard: failed to restore Plasma animations; will retry' >&2
              fi
            fi
          fi

          if [ "$max_samples" -gt 0 ] && [ "$sample_count" -ge "$max_samples" ]; then
            exit 0
          fi
        done
  '';
in {
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

    systemd.user.services.memory-animation-guard = {
      description = "Disable Plasma animations under sustained memory pressure";
      after = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      wantedBy = ["graphical-session.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${memoryAnimationGuard}/bin/memory-animation-guard";
        Restart = "on-failure";
        RestartSec = 5;
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

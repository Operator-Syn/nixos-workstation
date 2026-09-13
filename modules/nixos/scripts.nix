{pkgs, ...}: let
  getGPU = pkgs.writeShellScriptBin "getGPU" ''
    ${pkgs.pciutils}/bin/lspci | grep -E "VGA|3D" | awk '{
        type = "Unknown"
        if ($0 ~ /[Nn][Vv][Ii][Dd][Ii][Aa]/) type = "NVIDIA"
        else if ($0 ~ /[Ii][Nn][Tt][Ee][Ll]/) type = "Intel"

        pci_id = $1
        gsub(/\./, ":", pci_id)

        print type ": PCI:" pci_id
    }'
  '';

  nvrun = pkgs.writeShellScriptBin "nvrun" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export GAMEMODE_DEBUG=0
    exec ${pkgs.gamemode}/bin/gamemoderun "$@"
  '';

  update-hardware = pkgs.writeShellScriptBin "update-hardware" ''
    set -e
    CONFIG_DIR="$HOME/nix-config"
    HARDWARE_FILE="$CONFIG_DIR/hosts/hiraeth/hardware-configuration.nix"
    TEMP_FILE=$(mktemp)

    echo "Authenticating for hardware scan..."
    sudo -v

    echo "Scanning hardware for changes..."
    sudo nixos-generate-config --dir $(mktemp -d) --show-hardware-config 2>/dev/null \
      | awk '
          /fileSystems\."\/var\/lib\/(containers|docker)/ { skip=1 }
          skip && /};/ { skip=0; next }
          !skip
        ' > "$TEMP_FILE"

    if diff -q "$TEMP_FILE" "$HARDWARE_FILE" > /dev/null; then
        echo "No hardware changes detected."
    else
        echo "Hardware changes detected! Updating configuration..."
        cp "$TEMP_FILE" "$HARDWARE_FILE"
        echo "Successfully updated $HARDWARE_FILE"
    fi
    rm "$TEMP_FILE"
  '';

  update-system = pkgs.writeShellScriptBin "update-system" ''
    interrupt_cleanup() {
      sudo -k
      echo -e "\n[!] Update interrupted. Credentials cleared."
      exit 130
    }

    fail_cleanup() {
      sudo -k
      echo -e "\n[!] Update failed. Credentials cleared."
      exit 1
    }

    trap interrupt_cleanup SIGINT SIGTERM

    echo "Updating flake inputs..."
    nix flake update --flake "$HOME/nix-config" --cores "$(nproc)" || fail_cleanup

    ${rebuild}/bin/rebuild || fail_cleanup

    sudo -k
  '';

  update-codex = pkgs.writeShellScriptBin "update-codex" ''
    exec ${pkgs.bash}/bin/bash "$HOME/nix-config/scripts/update_codex.sh" "$@"
  '';

  hermes-restart = pkgs.writeShellScriptBin "hermes-restart" ''
        set -euo pipefail

        systemctl="${pkgs.systemd}/bin/systemctl"
        ps="${pkgs.procps}/bin/ps"
        awk="${pkgs.gawk}/bin/awk"
        sleep="${pkgs.coreutils}/bin/sleep"
        nohup="${pkgs.coreutils}/bin/nohup"
        gateway_unit="hermes-gateway.service"

        usage() {
          cat >&2 <<'EOF'
    Usage: hermes-restart [--all|--gateway|--desktop]

      --all      Restart the gateway and restart Desktop if it is already running.
      --gateway  Restart only the Hermes gateway user service.
      --desktop  Restart Desktop, starting it if it is currently closed.
    EOF
        }

        mode="all"
        case "''${1:-}" in
          ""|--all) ;;
          --gateway) mode="gateway" ;;
          --desktop) mode="desktop" ;;
          --help|-h)
            usage >&1
            exit 0
            ;;
          *)
            usage
            exit 2
            ;;
        esac

        if [ "$#" -gt 1 ]; then
          usage
          exit 2
        fi

        desktop_pids() {
          "$ps" -eo pid=,args= | "$awk" '$0 ~ /[e]lectron.*hermes-desktop/ {print $1}'
        }

        restart_gateway() {
          if ! "$systemctl" --user cat "$gateway_unit" >/dev/null 2>&1; then
            echo "Hermes gateway unit not found: $gateway_unit" >&2
            return 1
          fi

          echo "Restarting $gateway_unit..."
          "$systemctl" --user restart "$gateway_unit"
          if ! "$systemctl" --user is-active --quiet "$gateway_unit"; then
            echo "Hermes gateway did not become active." >&2
            "$systemctl" --user --no-pager --full status "$gateway_unit" || true
            return 1
          fi
          echo "Hermes gateway is active."
        }

        stop_desktop() {
          local pids
          pids="$(desktop_pids)"
          if [ -z "$pids" ]; then
            return 0
          fi

          echo "Stopping Hermes Desktop and its local backends..."
          while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill -TERM "$pid" 2>/dev/null || true
          done <<< "$pids"

          for _ in {1..50}; do
            [ -z "$(desktop_pids)" ] && return 0
            "$sleep" 0.2
          done

          echo "Hermes Desktop did not exit cleanly; refusing to launch a duplicate." >&2
          return 1
        }

        start_desktop() {
          local launcher
          launcher="$(command -v hermes-desktop || true)"
          if [ -z "$launcher" ]; then
            echo "hermes-desktop is not available in PATH." >&2
            return 1
          fi

          echo "Starting Hermes Desktop..."
          "$nohup" "$launcher" >/dev/null 2>&1 </dev/null &
          for _ in {1..50}; do
            if [ -n "$(desktop_pids)" ]; then
              echo "Hermes Desktop launch requested."
              return 0
            fi
            "$sleep" 0.2
          done

          echo "Hermes Desktop did not appear after launch." >&2
          return 1
        }

        desktop_was_running=false
        if [ "$mode" = "all" ] || [ "$mode" = "desktop" ]; then
          if [ -n "$(desktop_pids)" ]; then
            desktop_was_running=true
            stop_desktop
          fi
        fi

        if [ "$mode" = "all" ] || [ "$mode" = "gateway" ]; then
          restart_gateway
        fi

        if [ "$mode" = "desktop" ] || [ "$desktop_was_running" = true ]; then
          start_desktop
        fi
  '';

  rebuild = pkgs.writeShellScriptBin "rebuild" ''
    sudo=/run/wrappers/bin/sudo
    sudo_keepalive_pid=""

    stop_sudo_keepalive() {
      if test -n "$sudo_keepalive_pid"; then
        kill "$sudo_keepalive_pid" 2>/dev/null || true
        wait "$sudo_keepalive_pid" 2>/dev/null || true
        sudo_keepalive_pid=""
      fi
    }

    cleanup() {
      stop_sudo_keepalive
      "$sudo" -k
      echo -e "\n[!] Build interrupted. Credentials cleared."
      exit 1
    }

    trap cleanup SIGINT SIGTERM

    echo "Authenticating once for the rebuild..."
    "$sudo" -v
    (
      while "$sudo" -n -v >/dev/null 2>&1; do
        sleep 60
      done
    ) &
    sudo_keepalive_pid=$!

    ${update-hardware}/bin/update-hardware || cleanup

    echo "Starting NixOS Rebuild..."
    "$sudo" -n nixos-rebuild switch --flake "$HOME/nix-config/#nixos" --cores "$(nproc)" --show-trace || cleanup

    stop_sudo_keepalive
    trap - EXIT
  '';

  wifi-hotspot = pkgs.writeShellScriptBin "wifi-hotspot" ''
    set -euo pipefail

    nmcli=${pkgs.networkmanager}/bin/nmcli
    interface="''${1:-}"
    ssid="''${2:-}"
    connection="''${3:-}"

    if [ "$#" -gt 3 ]; then
      echo "Usage: wifi-hotspot [interface] [ssid] [connection-name]" >&2
      exit 2
    fi

    if [ -z "$interface" ]; then
      while IFS=: read -r candidate type state; do
        [ "$type" = "wifi" ] || continue
        [ "$state" = "connected" ] || [ "$state" = "disconnected" ] || continue
        [ "$("$nmcli" -g WIFI-PROPERTIES.AP device show "$candidate")" = "yes" ] || continue
        interface="$candidate"
        break
      done < <("$nmcli" -t -f DEVICE,TYPE,STATE device status)
    fi

    if [ -z "$interface" ]; then
      echo "No Wi-Fi adapter with AP support was found." >&2
      exit 1
    fi

    if [ -z "$ssid" ]; then
      read -r -p "Hotspot SSID: " ssid
    fi
    if [ -z "$ssid" ]; then
      echo "The hotspot SSID cannot be empty." >&2
      exit 1
    fi

    if [ -z "$connection" ]; then
      connection="$ssid"
    fi

    if ! "$nmcli" -t -f DEVICE,TYPE,STATE device status |
      awk -F: '$2 == "ethernet" && $3 == "connected" { found = 1 } END { exit !found }'
    then
      echo "An active Ethernet connection is required for internet sharing." >&2
      exit 1
    fi

    printf 'Hotspot password (at least 8 characters): '
    read -r -s password
    printf '\n'

    if [ ''${#password} -lt 8 ]; then
      echo "The hotspot password must contain at least 8 characters." >&2
      exit 1
    fi

    if "$nmcli" connection show "$connection" >/dev/null 2>&1; then
      profile_type="$("$nmcli" -g connection.type connection show "$connection")"
      if [ "$profile_type" != "802-11-wireless" ]; then
        echo "The connection name belongs to a non-Wi-Fi profile: $connection" >&2
        exit 1
      fi

      "$nmcli" connection modify "$connection" \
        802-11-wireless.ssid "$ssid" \
        802-11-wireless.mode ap \
        802-11-wireless.band "" \
        802-11-wireless.channel "" \
        ipv4.method shared \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$password"
    else
      "$nmcli" device wifi hotspot \
        ifname "$interface" \
        con-name "$connection" \
        ssid "$ssid" \
        password "$password"

      "$nmcli" connection modify "$connection" \
        802-11-wireless.mode ap \
        802-11-wireless.band "" \
        802-11-wireless.channel "" \
        ipv4.method shared
    fi

    exec "$nmcli" connection up "$connection" ifname "$interface"
  '';
in {
  environment.systemPackages = [
    getGPU
    hermes-restart
    nvrun
    rebuild
    update-codex
    update-hardware
    update-system
    wifi-hotspot
  ];
}

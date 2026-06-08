{pkgs, ...}: let
  # Creates a system-wide command to find GPU Bus IDs
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

  # Creates a system-wide 'nvrun' command
  nvrun = pkgs.writeShellScriptBin "nvrun" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GL_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export GAMEMODE_DEBUG=0
    exec ${pkgs.gamemode}/bin/gamemoderun "$@"
  '';

  # Automated hardware scan and copy script
  update-hardware = pkgs.writeShellScriptBin "update-hardware" ''
    set -e
    TARGET_DIR="$HOME/nix-config"
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

    if diff -q "$TEMP_FILE" "$TARGET_DIR/hardware-configuration.nix" > /dev/null; then
        echo "No hardware changes detected."
    else
        echo "Hardware changes detected! Updating configuration..."
        cp "$TEMP_FILE" "$TARGET_DIR/hardware-configuration.nix"
        echo "Successfully updated $TARGET_DIR/hardware-configuration.nix"
    fi
    rm "$TEMP_FILE"
  '';

  # Enhanced rebuild command with automated flags and security cleanup
  rebuild = pkgs.writeShellScriptBin "rebuild" ''
    # Cleanup function to wipe sudo credentials on interrupt
    cleanup() {
      sudo -k
      echo -e "\n[!] Build interrupted. Credentials cleared."
      exit 1
    }

    # Trap SIGINT (Ctrl+C) and SIGTERM
    trap cleanup SIGINT SIGTERM

    # Run hardware update; if it fails or is interrupted, the script stops here
    ${update-hardware}/bin/update-hardware || cleanup

    # Execute the switch with your MSI's 16 cores
    echo "Starting NixOS Rebuild..."
    sudo nixos-rebuild switch --flake $HOME/nix-config/#nixos --cores 16 --show-trace || cleanup

    # Optional: clear sudo at the very end to stay locked
    # echo "Flushing credentials"
    # sudo -k
  '';
in [getGPU nvrun update-hardware rebuild]

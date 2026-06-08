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
    export __GL_VENDOR_LIBRARY_NAME=nvidia
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

  rebuild = pkgs.writeShellScriptBin "rebuild" ''
    cleanup() {
      sudo -k
      echo -e "\n[!] Build interrupted. Credentials cleared."
      exit 1
    }

    trap cleanup SIGINT SIGTERM

    ${update-hardware}/bin/update-hardware || cleanup

    echo "Starting NixOS Rebuild..."
    sudo nixos-rebuild switch --flake "$HOME/nix-config/#nixos" --cores "$(nproc)" --show-trace || cleanup

    # Optional: clear sudo at the very end to stay locked
    # echo "Flushing credentials"
    # sudo -k
  '';
in {
  environment.systemPackages = [
    getGPU
    nvrun
    rebuild
    update-hardware
  ];
}

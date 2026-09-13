{inputs, lib, ...}: {
  imports = [
    inputs.aagl.nixosModules.default
    ./hardware-configuration.nix
    ./storage.nix
    ./boot.nix
    ./nvidia.nix

    ../../modules/nixos/core
    ../../modules/nixos/desktop/audio-tools.nix
    ../../modules/nixos/desktop/obs-studio.nix
    ../../modules/nixos/desktop/plasma.nix
    ../../modules/nixos/desktop/power-profile-enforcer.nix

    ../../modules/nixos/development/nix-ld.nix
    ../../modules/nixos/development/python-shell.nix
    ../../modules/nixos/development/distrobox.nix
    ../../modules/nixos/development/distrobox-debian-dev.nix
    # ../../modules/nixos/development/debian-container.nix

    ../../modules/nixos/hardware/bluetooth.nix
    ../../modules/nixos/hardware/asus.nix

    ../../modules/nixos/networking.nix
    ../../modules/nixos/openssh.nix
    ../../modules/nixos/netbird.nix
    ../../modules/nixos/packages.nix
    ../../modules/nixos/users/yashindo.nix
    ../../modules/nixos/kvm-manager.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/steam.nix
    ../../modules/nixos/bedrock-on-linux
  ];

  nix.settings = inputs.aagl.nixConfig;

  networking.hostName = "Hiraeth";

  # Keep zram first, then spill to NVMe-backed swap before a global OOM.
  swapDevices = [
    {
      # nixpkgs-25.11 currently evaluates the optional label field eagerly.
      label = "";
      device = lib.mkForce "/swapfile";
      size = 16384;
      priority = 10;
    }
  ];

  modules = {
    netbird.enable = true;
    openssh.enable = true;
    steam.enable = true;
    bedrock-on-linux.enable = true;
    kvm-manager.enable = true;

    distrobox.debian-dev.enable = true;
    # debian-container.enable = true;

    python-shell.enable = true;
    asus.enable = true;
  };

  hostStorage.enable = true;

  system.stateVersion = "25.11";
}

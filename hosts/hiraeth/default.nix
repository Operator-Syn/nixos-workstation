{...}: {
  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./nvidia.nix

    ../../modules/nixos/core
    ../../modules/nixos/desktop/plasma.nix
    ../../modules/nixos/development/python-shell.nix
    ../../modules/nixos/development/distrobox.nix
    ../../modules/nixos/development/distrobox-debian-dev.nix
    # ../../modules/nixos/development/debian-container.nix
    ../../modules/nixos/hardware/bluetooth.nix
    ../../modules/nixos/hardware/msi.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/packages.nix
    ../../modules/nixos/users/yashindo.nix
    ../../modules/nixos/virtualisation.nix
  ];

  networking.hostName = "Hiraeth";

  modules = {
    distrobox.debian-dev.enable = true;
    # debian-container.enable = true;
    # python-shell.enable = true;
  };

  system.stateVersion = "25.11";
}

{inputs, ...}: {
  imports = [
    inputs.aagl.nixosModules.default
    inputs.sops-nix.nixosModules.sops

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
    ../../modules/nixos/hermes.nix
    ../../modules/nixos/hermes-ssh.nix
    ../../modules/nixos/obsidian-hermes-vault.nix
    ../../modules/nixos/graphify.nix
    ../../modules/nixos/hermes-graphify.nix
    ../../modules/nixos/users/yashindo.nix
    ../../modules/nixos/kvm-manager.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/steam.nix
  ];

  sops.age.keyFile = "/home/yashindo/.config/sops/age/keys.txt";
  sops.secrets.gh_token = {
    sopsFile = ../../secrets/gh.yaml;
    key = "token";
    path = "/run/hermes/gh/feilhann.token";
    owner = "yashindo";
    group = "users";
    mode = "0400";
  };
  sops.secrets.gh_operator_syn_token = {
    sopsFile = ../../secrets/gh.yaml;
    key = "operator_syn_token";
    path = "/run/hermes/gh/operator-syn.token";
    owner = "yashindo";
    group = "users";
    mode = "0400";
  };
  sops.secrets.hermes_ssh_id_ed25519 = {
    sopsFile = ../../secrets/ssh.yaml;
    key = "data";
    path = "/run/hermes/ssh/id_ed25519";
    owner = "yashindo";
    group = "users";
    mode = "0400";
  };

  nix.settings = inputs.aagl.nixConfig;

  networking.hostName = "Hiraeth";

  modules = {
    netbird.enable = true;
    openssh.enable = true;
    steam.enable = true;
    kvm-manager.enable = true;

    distrobox.debian-dev.enable = true;
    # debian-container.enable = true;

    python-shell.enable = true;
    asus.enable = true;
    hermes.enable = true;
    obsidianHermesVault.enable = true;
    graphify.enable = true;
    hermes.graphify.enable = true;
  };

  hostStorage.enable = true;

  system.stateVersion = "25.11";
}

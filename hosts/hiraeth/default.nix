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
    ../../modules/nixos/netbird.nix
    ../../modules/nixos/packages.nix
    ../../modules/nixos/security/home-acl.nix
    ../../modules/nixos/hermes.nix
    ../../modules/nixos/obsidian-hermes-vault.nix
    ../../modules/nixos/graphify.nix
    ../../modules/nixos/hermes-graphify.nix
    ../../modules/nixos/users/feilhann.nix
    ../../modules/nixos/users/yashindo.nix
    ../../modules/nixos/kvm-manager.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/steam.nix
  ];

  sops.age.keyFile = "/home/yashindo/.config/sops/age/keys.txt";
  sops.secrets.gh_token = {
    sopsFile = ../../secrets/gh.yaml;
    key = "token";
    owner = "feilhann";
    group = "feilhann";
    mode = "0400";
  };

  nix.settings = inputs.aagl.nixConfig;

  networking.hostName = "Hiraeth";

  modules = {
    netbird.enable = true;
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

  services.homeAcl.policies = [
    {
      name = "hermes-home-audit";
      reader = "feilhann";
      readerGroup = "hermes-audit-readonly";
      target = "yashindo";
      excludeDirectories = ["Git"];
    }
    {
      name = "hermes-projects-write";
      reader = "feilhann";
      readerGroup = "hermes-projects-write";
      target = "yashindo";
      paths = ["Git"];
      administrators = ["yashindo"];
      access = "read-write";
    }
    {
      name = "feilhann-home-admin";
      reader = "yashindo";
      readerGroup = "feilhann-home-admin";
      target = "feilhann";
      administrators = ["yashindo"];
      access = "read-write";
    }
    # ── ADDED: declarative write grant for feilhann on nix-config ──
    {
      name = "hermes-nix-config-write";
      reader = "feilhann";
      target = "yashindo";
      paths = ["nix-config"];
      administrators = ["yashindo"];
      access = "read-write";
    }
    {
      name = "hermes-vault-admin";
      reader = "feilhann";
      readerGroup = "obsidian-hermes";
      target = "yashindo";
      root = "/srv/obsidian/hermes-vault";
      administrators = ["yashindo"];
      access = "read-write";
    }
  ];

  systemd.services.home-acl-reconcile = {
    after = ["hermes-desktop-backend.service"];
    wants = [
      "hermes-desktop-backend.service"
      "systemd-tmpfiles-resetup.service"
    ];
  };

  system.stateVersion = "25.11";
}

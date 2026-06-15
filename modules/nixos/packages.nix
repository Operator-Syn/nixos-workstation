{pkgs, ...}: {
  imports = [
    ./scripts.nix
  ];

  environment.systemPackages = with pkgs; [
    alejandra
    docker-compose
    easyeffects
    gamemode
    git
    nil
    nixfmt-rfc-style
    nodejs_24
    bun
    pavucontrol
    tree
    openssl
    rustc
    cargo
    clippy
    rustfmt

    kdePackages.partitionmanager
    kdePackages.aurorae
    kdePackages.breeze
    kdePackages.kconfig
    kdePackages.kcoreaddons
    kdePackages.kdecoration
    kdePackages.plasma-browser-integration
    kdePackages.polkit-kde-agent-1
    kdePackages.qttools
  ];


}

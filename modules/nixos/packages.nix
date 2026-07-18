{ pkgs, ... }: {
  imports = [
    ./scripts.nix
  ];

  environment.systemPackages = with pkgs; [
    alejandra
    docker-compose
    easyeffects
    gamemode
    git
    ripgrep
    nil
    nixfmt-rfc-style
    nodejs_24
    bun
    pavucontrol
    kdePackages.kamoso
    kdePackages.qrca
    zbar
    tcpdump
    tree
    openssl
    wl-clipboard
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

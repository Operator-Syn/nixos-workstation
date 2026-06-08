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
    pavucontrol
    tree

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

{pkgs, ...}: {
  home.packages = with pkgs; [
    bat
    btop
    cudaPackages.cudatoolkit
    exfat
    fzf
    inkscape
    inter
    inter-nerdfont
    kdePackages.kdegraphics-thumbnailers
    kdePackages.kirigami
    kdePackages.kirigami-addons
    kdePackages.qwt
    lsd
    miracode
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    openmpi
    # pipenv
    claude-code
    ripgrep
    vlc
    zoxide
    zoom-us
  ];
}

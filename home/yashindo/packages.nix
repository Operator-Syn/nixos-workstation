{pkgs, ...}: {
  home.packages = with pkgs; [
    bat
    btop
    cudaPackages.cudatoolkit
    exfat
    fzf
    gparted
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
    vlc
    zoxide
    zoom-us
  ];
}

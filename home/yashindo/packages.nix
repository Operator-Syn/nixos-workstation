{
  pkgs,
  pkgsUnstable,
  ...
}: {
  home.packages = with pkgs; [
    bat
    biome
    btop
    cudaPackages.cudatoolkit
    exfat
    fzf
    inkscape
    inter
    inter-nerdfont
    kdePackages.kirigami
    kdePackages.kirigami-addons
    kdePackages.qwt
    lsd
    miracode
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    openmpi
    (python3.withPackages (pythonPackages: [
      pythonPackages.pytest
    ]))
    # pipenv
    claude-code
    pkgsUnstable.opencode
    vlc
    zoxide
    zoom-us
  ];
}

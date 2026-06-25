{
  imports = [
    ./alacritty.nix
    ./alacritty-widget.nix
    ./brave.nix
    ./cava.nix
    ./direnv.nix
    ./discord.nix
    ./discord-pro.nix
    ./fastfetch.nix
    ./firefox.nix
    ./fish.nix
    ./git.nix
    ./latex.nix
    ./libreoffice.nix
    ./obs-studio.nix
    ./prisma.nix
    ./castersoundboard.nix
    ./spotify.nix
    ./spotifyd.nix
    ./spotify-player.nix
    ./ssh.nix
    ./starship.nix
    ./vscode.nix
    ./winboat.nix
    ./youtube-dl.nix
    ./easyeffects-module.nix
  ];

  modules = {
    alacritty.enable = true;
    alacritty-widget.enable = false;
    brave.enable = true;
    cava.enable = true;
    direnv.enable = true;
    discord.enable = true;
    discord-pro.enable = true;
    fastfetch.enable = true;
    firefox.enable = true;
    fish.enable = true;
    git.enable = true;
    latex.enable = true;
    libreoffice.enable = true;
    obs-studio.enable = true;
    prisma.enable = true;
    castersoundboard.enable = true;
    spotify.enable = true;
    spotifyd.enable = true;
    spotify-player.enable = false;
    ssh.enable = true;
    starship.enable = true;
    vscode.enable = true;
    winboat.enable = true;
    youtube-dl.enable = true;
    easyeffects.enable = true;
  };
}

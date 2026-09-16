{
  imports = [
    ./alacritty.nix
    ./alacritty-widget.nix
    ./brave.nix
    ./cava.nix
    ./audacity.nix
    ./direnv.nix
    ./discord.nix
    ./discord-pro.nix
    ./fastfetch.nix
    ./firefox.nix
    ./fish.nix
    ./git.nix
    ./gh.nix
    ./goose.nix
    ./hermes-desktop.nix
    ./latex.nix
    ./libreoffice.nix
    ./ncspot.nix
    ./obs-studio.nix
    ./obsidian.nix
    ./peak-hours.nix
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
    ./blender.nix
  ];

  modules = {
    alacritty.enable = true;
    alacritty-widget.enable = false;
    brave.enable = true;
    cava.enable = true;
    audacity.enable = true;
    direnv.enable = true;
    discord.enable = true;
    discord-pro.enable = false;
    fastfetch.enable = true;
    firefox.enable = true;
    fish.enable = true;
    git.enable = true;
    gh.enable = true;
    goose.enable = false;
    hermes-desktop.enable = true;
    latex.enable = true;
    libreoffice.enable = true;
    obs-studio.enable = true;
    obsidian.enable = true;
    peak-hours.enable = true;
    prisma.enable = true;
    castersoundboard.enable = true;
    ncspot.enable = true;
    spotify.enable = false;
    spotifyd.enable = false;
    spotify-player.enable = false;
    ssh.enable = true;
    starship.enable = true;
    vscode.enable = true;
    winboat.enable = false;
    youtube-dl.enable = true;
    easyeffects.enable = true;
    blender.enable = true;
  };
}

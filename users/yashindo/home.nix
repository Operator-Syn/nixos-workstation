{
  config,
  pkgs,
  inputs,
  ...
}: {
  home.username = "yashindo";
  home.homeDirectory = "/home/yashindo";

  imports = [
    ./apps/vscode.nix
    ./apps/brave.nix
    ./apps/alacritty.nix
    ./apps/fish.nix
    ./apps/starship.nix
    ./apps/firefox.nix
    ./apps/discord.nix
    ./apps/discord-pro.nix
    ./apps/spotify_player.nix
    ./apps/cava.nix
    ./apps/winboat.nix
    ./apps/youtube-dl.nix
    ./apps/fastfetch.nix
    ./apps/alacritty-widget.nix
    ./apps/latext.nix

    # ./development/python-shell.nix

    inputs.plasma-manager.homeModules.plasma-manager
    ./plasma-config/taskbar-panel.nix
    ./plasma-config/wobbly_windows.nix
    ./plasma-config/desktop-settings.nix
    ./plasma-config/icons/candy-icons.nix
    ./plasma-config/colors/sweet-nova.nix
    ./plasma-config/wallpaper/scarlet-tree.nix
    ./plasma-config/session-manager/session-manager.nix
    ./plasma-config/window-decoration/layan.nix
    ./plasma-config/magic_lamp.nix
  ];

  # --- App Toggles ---
  # Set to false to remove the App
  modules.winboat.enable = true;
  modules.vscode.enable = true;
  modules.brave.enable = true;
  modules.alacritty.enable = true;
  modules.fish.enable = true;
  modules.starship.enable = true;
  modules.firefox.enable = true;
  modules.discord.enable = true;
  modules.discord-pro.enable = true;
  modules.spotify-player.enable = false;
  modules.cava.enable = true;
  modules.youtube-dl.enable = true;
  modules.fastfetch.enable = true;
  modules.alacritty-widget.enable = false;
  modules.latex.enable = true;

  # modules.python-shell.enable = true;

  modules.layan.enable = true;
  modules.scarlet-tree.enable = true;
  modules.candyIcons.enable = true;
  modules.sweetNova.enable = true;
  modules.taskbar-panel.enable = true;

  programs.wobbly-windows.enable = true;
  programs.magic-lamp.enable = true;
  # -------------------

  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Add your user-specific packages here
  home.packages = with pkgs; [
    # Utilities
    lsd
    bat
    fzf
    zoxide

    # Fonts
    nerd-fonts.fira-code
    miracode
    inter-nerdfont
    inter
    nerd-fonts.fira-mono

    # Development Runtimes & Package Managers
    pipenv
    nodejs_24
    pnpm
    bun
    vlc
    openmpi #temporary
    gparted
    exfat

    zoom-us
    btop
    inkscape

    # AI/ML & Research Support
    cudaPackages.cudatoolkit
    kdePackages.qwt

    # Aesthetics
    kdePackages.kdegraphics-thumbnailers
    kdePackages.kirigami
    kdePackages.kirigami-addons
  ];
}

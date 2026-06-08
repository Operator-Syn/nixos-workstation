{
  imports = [
    ./colors/sweet-nova.nix
    ./desktop-settings.nix
    ./icons/candy-icons.nix
    ./magic-lamp.nix
    ./session-manager/session-manager.nix
    ./taskbar-panel.nix
    ./wallpaper/scarlet-tree.nix
    ./window-decoration/layan.nix
    ./wobbly-windows.nix
  ];

  modules = {
    candyIcons.enable = true;
    layan.enable = true;
    scarlet-tree.enable = true;
    sweetNova.enable = true;
    taskbar-panel.enable = true;
  };

  programs = {
    magic-lamp.enable = true;
    wobbly-windows.enable = true;
  };
}

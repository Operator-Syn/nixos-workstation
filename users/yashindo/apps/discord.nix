{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.discord.enable = lib.mkEnableOption "Discord";

  config = lib.mkIf config.modules.discord.enable {
    home.packages = with pkgs; [
      discord
    ];

    # Skip update check and start minimized
    home.file.".config/discord/settings.json".text = builtins.toJSON {
      SKIP_HOST_UPDATE = true;
    };

    # This creates a .desktop file in ~/.config/autostart/
    xdg.configFile."autostart/discord.desktop".text = ''
      [Desktop Entry]
      Name=Discord
      Exec=${lib.getExe pkgs.discord} --start-minimized
      Type=Application
      Categories=Network;InstantMessaging;
      X-GNOME-Autostart-enabled=true
    '';
  };
}

{
  pkgsUnstable,
  lib,
  config,
  ...
}: {
  options.modules.discord.enable = lib.mkEnableOption "Discord";

  config = lib.mkIf config.modules.discord.enable {
    home.packages = [pkgsUnstable.discord];

    # Skip update check and start minimized
    home.file.".config/discord/settings.json".text = builtins.toJSON {
      SKIP_HOST_UPDATE = true;
    };

    # Autostart minimized, with no launcher prompt. The application menu entry
    # comes from the Discord package itself.
    xdg.configFile."autostart/discord.desktop".text = ''
      [Desktop Entry]
      Name=Discord
      Exec=${lib.getExe pkgsUnstable.discord} --start-minimized
      Type=Application
      Categories=Network;InstantMessaging;
      X-GNOME-Autostart-enabled=true
    '';
  };
}

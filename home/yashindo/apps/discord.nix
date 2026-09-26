{
  pkgsUnstable,
  lib,
  config,
  ...
}: let
  discordAutostart = pkgsUnstable.writeShellScriptBin "discord-autostart" ''
    # Wait for the Discord update service hostname to resolve before starting
    # the login instance. Manual launches still use the package launcher.
    while ! ${pkgsUnstable.getent}/bin/getent ahosts discord.com. >/dev/null 2>&1; do
      ${pkgsUnstable.coreutils}/bin/sleep 2
    done

    exec ${lib.getExe pkgsUnstable.discord} "$@"
  '';
in {
  options.modules.discord.enable = lib.mkEnableOption "Discord";

  config = lib.mkIf config.modules.discord.enable {
    home.packages = [
      pkgsUnstable.discord
      discordAutostart
    ];

    # Skip update check
    home.file.".config/discord/settings.json".text = builtins.toJSON {
      SKIP_HOST_UPDATE = true;
    };

    # Start minimized in the tray at login. The application menu entry comes
    # from the Discord package itself.
    xdg.configFile."autostart/discord.desktop".text = ''
      [Desktop Entry]
      Name=Discord
      Exec=${lib.getExe discordAutostart} --start-minimized
      Type=Application
      Categories=Network;InstantMessaging;
      X-GNOME-Autostart-enabled=true
    '';
  };
}

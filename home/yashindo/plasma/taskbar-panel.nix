{
  config,
  lib,
  pkgs,
  ...
}: {
  options.modules.taskbar-panel.enable = lib.mkEnableOption "KDE Plasma Bottom Panel";

  config = lib.mkIf config.modules.taskbar-panel.enable {
    home.file.".local/share/icons/NixOS.svg".source = ./icons/NixOS.svg;

    xdg.mimeApps = {
      enable = true;
      defaultApplications."inode/directory" = ["org.kde.dolphin.desktop"];
    };

    programs.plasma = {
      enable = true;
      overrideConfig = true;
      panels = [
        {
          location = "bottom";
          height = 48;
          floating = true;
          widgets = [
            {
              name = "org.kde.plasma.kickoff";
              config.General.icon = "${config.home.homeDirectory}/.local/share/icons/NixOS.svg";
            }
            "org.kde.plasma.pager"
            {
              name = "org.kde.plasma.icontasks";
              config.General = {
                groupingStrategy = 0;
                launchers = [
                  "applications:systemsettings.desktop"
                  "applications:org.kde.dolphin.desktop"
                  "applications:firefox.desktop"
                  "applications:brave-browser.desktop"
                  "applications:code.desktop"
                  "applications:Alacritty.desktop"
                ];
              };
            }
            "org.kde.plasma.marginsseparator"
            "org.kde.plasma.systemtray"
            "org.kde.plasma.digitalclock"
            "org.kde.plasma.showdesktop"
          ];
          hiding = "none";
        }
      ];
    };
  };
}

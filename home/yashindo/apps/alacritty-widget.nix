{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.alacritty-widget.enable = lib.mkEnableOption "Fastfetch Desktop Widget";

  config = lib.mkIf config.modules.alacritty-widget.enable {
    home.packages = [pkgs.plasma-applet-commandoutput];

    xdg.dataFile."plasma/plasmoids/com.github.zren.commandoutput".source = "${pkgs.plasma-applet-commandoutput}/share/plasma/plasmoids/com.github.zren.commandoutput";

    programs.plasma.desktop.widgets = [
      {
        name = "com.github.zren.commandoutput";
        position = {
          horizontal = 1450;
          vertical = 750;
        };
        size = {
          width = 450;
          height = 300;
        };
        config = {
          General = {
            command = "${pkgs.fastfetch}/bin/fastfetch --pipe";
            interval = "0";
            showBackground = "false";
            showTitle = "false";
          };
        };
      }
    ];
  };
}

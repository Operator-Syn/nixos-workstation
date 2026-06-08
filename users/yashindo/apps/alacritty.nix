{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.alacritty.enable = lib.mkEnableOption "Alacritty Terminal";

  config = lib.mkIf config.modules.alacritty.enable {
    programs.alacritty = {
      enable = true;
      package = pkgs.alacritty-graphics;

      settings = {
        terminal.shell = {
          program = "${pkgs.fish}/bin/fish";
          # Added -C (command) to run fastfetch before starting the interactive shell
          args = ["-C" "fastfetch" "--login"];
        };

        window = {
          opacity = 0.9;
          padding = {
            x = 12;
            y = 12;
          };
          dynamic_title = true;
        };

        font = {
          normal = {
            family = "FiraCode Nerd Font";
            style = "Regular";
          };
          bold = {
            family = "FiraCode Nerd Font";
            style = "Bold";
          };
          size = 11.0;
        };

        cursor.style = "Beam";

        colors = {
          primary = {
            background = "#1d1f21";
            foreground = "#c5c8c6";
          };
        };
      };
    };

    fonts.fontconfig.enable = true;
  };
}

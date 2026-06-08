{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.modules.fastfetch;
in {
  options.modules.fastfetch.enable = lib.mkEnableOption "Fastfetch";

  config = lib.mkIf cfg.enable {
    programs.fastfetch = {
      enable = true;

      settings = {
        logo = {
          type = "sixel";
          source = "${config.home.homeDirectory}/.local/share/icons/Executor_Skin_1.png";
          width = 22;
          height = 11;
          padding = {
            top = 4;
            left = 1;
          };
        };

        display = {
          separator = "  ";
          color = {
            keys = "34";
            output = "37";
          };
          temp = {
            unit = "C"; # Keeps it standard
          };
        };

        modules = [
          {
            type = "custom";
            format = "{#34}┌── {#37}EXECUTOR PROTOCOL";
          }
          {
            type = "title";
            format = "{#34}│ {#37}ID: {user-name}@{host-name}";
          }
          {
            type = "custom";
            format = "{#34}├─";
          }

          # --- Hardware ---
          {
            type = "custom";
            format = "{#34}│ {#37}󰒋 HARDWARE";
          }
          {
            type = "host";
            key = "{#34}│ {#90}├─ {#37}Host";
          }
          {
            type = "cpu";
            key = "{#34}│ {#90}├─ {#37}CPU ";
            temp = true;
            format = "{1}";
          }
          {
            type = "gpu";
            key = "{#34}│ {#90}├─ {#37}GPU ";
            temp = true;
            format = "{2}"; # Shows the model name clearly
          }
          {
            type = "memory";
            key = "{#34}│ {#90}╰─ {#37}RAM ";
          }

          {
            type = "custom";
            format = "{#34}├─";
          }

          # --- Logic ---
          {
            type = "custom";
            format = "{#34}│ {#37}󰟆 LOGIC_CORE";
          }
          {
            type = "os";
            key = "{#34}│ {#90}├─ {#37}OS  ";
            format = "{2} {8}";
          }
          {
            type = "kernel";
            key = "{#34}│ {#90}├─ {#37}Kern";
          }
          {
            type = "wm";
            key = "{#34}│ {#90}╰─ {#37}WM  ";
          }

          {
            type = "custom";
            format = "{#34}├─";
          }

          # --- Interface ---
          {
            type = "custom";
            format = "{#34}│ {#37}󰉼 INTERFACE";
          }
          {
            type = "shell";
            key = "{#34}│ {#90}├─ {#37}Shel";
          }
          {
            type = "terminal";
            key = "{#34}│ {#90}╰─ {#37}Term";
          }

          {
            type = "custom";
            format = "{#34}└─";
          }

          "break"
          {
            type = "colors";
            symbol = "circle";
          }
        ];
      };
    };

    home.packages = [pkgs.libsixel];
    # Preserving comment: logic for icon source
    home.file.".local/share/icons/Executor_Skin_1.png".source = ../plasma-config/icons/Executor_Skin_1.png;
  };
}

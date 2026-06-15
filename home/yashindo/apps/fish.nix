{
  lib,
  config,
  ...
}: {
  options.modules.fish.enable = lib.mkEnableOption "Fish Shell";

  config = lib.mkIf config.modules.fish.enable {
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        set -g fish_greeting ""
        # Enable Vi keybindings if you prefer them over Emacs style
        fish_vi_key_bindings
        # Fix TERM only if it's invalid in containers
        if test "$TERM" = "alacritty"
          set -gx TERM xterm-256color
        end
        # Prevent BrokenPipeError noise from Python tools (e.g. nbstripout)
        set -gx PYTHONUNBUFFERED 1
      '';

      shellAliases = {
        # General aliases
        ls = "lsd -1 --group-directories-first --icon-theme fancy";
        la = "lsd -1a --group-directories-first";
        ll = "lsd -l --header --blocks permission,user,size,date,name --group-directories-first";
        tree = "lsd --tree";
        cat = "bat";

        # Link your existing custom scripts
        rb = "rebuild";
        uh = "update-hardware";
      };

      # Integration with your preferred TUI tools
      functions = {
        # Quick jump to config directory
        conf = "cd ~/nix-config";
        home = "cd ~ && clear";
        ".." = "cd ..";
        "..." = "cd ../..";
        dl = {
          description = "Download video with yt-dlp using Brave cookies";
          body = "yt-dlp --cookies-from-browser brave $argv";
        };
      };
    };
  };
}

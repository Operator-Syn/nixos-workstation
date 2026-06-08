{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.starship.enable = lib.mkEnableOption "Starship Prompt";

  config = lib.mkIf config.modules.starship.enable {
    programs.starship = {
      enable = true;
      enableFishIntegration = true;

      settings = {
        format = "[ λ ](bold yellow)[$username@$hostname:$directory]($style) $git_branch$git_status$python\n$character";

        add_newline = true;

        username = {
          show_always = true;
          style_user = "bold blue";
          format = "[$user]($style)";
        };

        hostname = {
          ssh_only = false;
          style = "bold blue";
          format = "[$hostname]($style)";
        };

        directory = {
          style = "bold blue";
          format = "[$path]($style)";
          truncation_length = 3;
          fish_style_pwd_dir_length = 1;
        };

        character = {
          success_symbol = "[╰─󰁔](bold green) ";
          error_symbol = "[╰─󰁔](bold red) ";
        };

        python = {
          symbol = "󰌠 ";
          style = "bold yellow";
          format = "via [$symbol]($style)[$version( \\($virtualenv\\))](bold green) ";
          detect_files = ["requirements.txt" "Pipfile" "pyproject.toml" ".python-version" "setup.py"];
          detect_extensions = ["py"];
          detect_folders = [".venv" "__pycache__"];
          python_binary = ["python" "python3" "python3.14"];
        };

        nix_shell = {
          symbol = "❄️ ";
          format = "via [$symbol$state]($style) ";
        };

        git_branch = {
          symbol = "󰘬 ";
          style = "bold purple";
          format = "on [$symbol$branch]($style) ";
        };

        git_status = {
          style = "bold red";
          format = "([\\[$all_status$ahead_behind\\]]($style) )";
          ahead = "⇡$count";
          behind = "⇣$count";
          diverged = "⇕⇡$ahead_count⇣$behind_count";
        };

        package.disabled = true;
      };
    };
  };
}

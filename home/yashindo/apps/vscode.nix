# vscode.nix
{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}: {
  options.modules.vscode.enable = lib.mkEnableOption "VS Code";

  config = lib.mkIf config.modules.vscode.enable {
    home.file.".local/share/applications/code-url-handler.desktop".text = ''
      [Desktop Entry]
      NoDisplay=true
    '';

    # Clean up old immutable VS Code extensions symlink.
    #
    # This fixes stale state where:
    #   ~/.vscode/extensions -> /nix/store/.../.vscode/extensions
    #
    # With mutableExtensionsDir = true, ~/.vscode/extensions needs to be a
    # normal writable directory so Home Manager can place individual extension
    # links inside it.
    home.activation.ensureMutableVscodeExtensionsDir = lib.hm.dag.entryBefore ["linkGeneration"] ''
      vscode_extensions="${config.home.homeDirectory}/.vscode/extensions"

      if [ -L "$vscode_extensions" ]; then
        target="$(${pkgs.coreutils}/bin/readlink -f "$vscode_extensions")"

        case "$target" in
          /nix/store/*)
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm "$vscode_extensions"
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$vscode_extensions"
            ;;
        esac
      fi
    '';

    programs.vscode = {
      enable = true;
      package = pkgsUnstable.vscode;
      mutableExtensionsDir = true;

      profiles.default = {
        extensions = with pkgs.vscode-extensions;
          [
            docker.docker
            ms-vscode-remote.remote-containers
            ms-azuretools.vscode-docker
            jnoortheen.nix-ide
            vscode-icons-team.vscode-icons
            leonardssh.vscord
            tomoki1207.pdf
          ]
          ++ [
            (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
              mktplcRef = {
                publisher = "ahmadalli";
                name = "vscode-nginx-conf";
                version = "0.3.1";
                sha256 = "sha256-wEz5DNWFm69zZDPILvDpLm3wJsqmrMa6ikYIClQOuZI=";
              };
            })

            (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
              mktplcRef = {
                publisher = "mathematic";
                name = "vscode-pdf";
                version = "0.1.11";
                sha256 = "sha256-h0liigU+oyHkZM9Kn3P8J/9IV8sgYI+fcpHV37WfNjk=";
              };
            })

            (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
              mktplcRef = {
                publisher = "samestep";
                name = "save-constantly";
                version = "0.1.0";
                sha256 = "sha256-s6M64yE1lx0mG/0zxYjNilMniflkAAhCxVccAU0jSEk=";
              };
            })
          ];

        userSettings = {
          "workbench.iconTheme" = "vscode-icons";

          "editor.fontFamily" = "'Miracode', 'FiraCode Nerd Font', monospace";
          "editor.fontLigatures" = true;
          "editor.fontSize" = 15;
          "editor.wordWrap" = "on";

          "terminal.integrated.fontFamily" = "'FiraCode Nerd Font'";
          "terminal.integrated.fontSize" = 15;
          "terminal.integrated.gpuAcceleration" = "on";

          "terminal.integrated.defaultProfile.linux" = "fish";
          "terminal.integrated.profiles.linux" = {
            fish = {
              path = "${pkgs.fish}/bin/fish";
            };
          };

          "saveConstantly.saveWithoutFormatting" = true;

          "git.openRepositoryInParentFolders" = "always";

          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "nil";
          "nix.formatterPath" = "alejandra";

          "nix.serverSettings" = {
            nil = {
              diagnostics = {
                ignored = [
                  "unused_binding"
                ];
              };

              formatting = {
                command = [
                  "alejandra"
                ];
              };
            };
          };

          "[nix]" = {
            "editor.defaultFormatter" = "jnoortheen.nix-ide";
            "editor.formatOnSave" = true;
          };

          "[nginx]" = {
            "editor.defaultFormatter" = "ahmadalli.vscode-nginx-conf";
          };

          "nix.extraPaths" = [
            "./."
          ];

          "claudeCode.preferredLocation" = "panel";

          "chat.editing.autoAcceptDelay" = 3;

          "vscord.app.name" = "Visual Studio Code";

          "chatgpt.reviewDelivery" = "detached";

          "files.autoSave" = "afterDelay";

          "json.schemaDownload.trustedDomains" = {
            "https://schemastore.azurewebsites.net/" = true;
            "https://raw.githubusercontent.com/microsoft/vscode/" = true;
            "https://raw.githubusercontent.com/devcontainers/spec/" = true;
            "https://www.schemastore.org/" = true;
            "https://json.schemastore.org/" = true;
            "https://json-schema.org/" = true;
            "https://developer.microsoft.com/json-schemas/" = true;
            "https://biomejs.dev" = true;
          };
        };
      };
    };

    # ------------------------------------------------------------------
    # IMPORTANT: DO NOT redefine full desktop entries for VS Code
    # Plasma + upstream VS Code already provide correct entries.
    # Overriding them causes duplicate launcher icons.
    # ------------------------------------------------------------------
  };
}

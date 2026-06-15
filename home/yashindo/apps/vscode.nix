# vscode.nix
{
  pkgs,
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

    programs.vscode = {
      enable = true;
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
                publisher = "teclado";
                name = "vscode-nginx-format";
                version = "0.0.6";
                sha256 = "sha256-Z85xNByHieBXykztwYWFMnvU974Ewc3Y5Nt3+B2YZVg=";
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
            "editor.defaultFormatter" = "teclado.vscode-nginx-format";
          };

          "nix.extraPaths" = [
            "./."
          ];

          "claudeCode.preferredLocation" = "panel";

          "chat.editing.autoAcceptDelay" = 3;
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

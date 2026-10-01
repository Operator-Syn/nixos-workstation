# vscode.nix
{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}: let
  cfg = config.modules.vscode;
  nixFormatter = "${pkgs.alejandra}/bin/alejandra";
  settingsPath = "${config.xdg.configHome}/Code/User/settings.json";
  stagedSettingsPath = "${config.xdg.configHome}/Code/User/.settings.json.hm-staged";
  vscodeBasePackage = pkgsUnstable.vscode.override {
    commandLineArgs = "--ozone-platform=x11";
  };
  vscodePackage = vscodeBasePackage.overrideAttrs (old: {
    postFixup =
      (old.postFixup or "")
      + ''
        ${pkgs.python3}/bin/python3 - "$out/lib/vscode/resources/app/extensions/copilot/dist/extension.js" <<'PY'
        from pathlib import Path
        import re
        import sys

        extension = Path(sys.argv[1])
        source = extension.read_text()
        # The Nix store copies are read-only; these generated shims must be writable.
        copy_pattern = re.compile(
            r"await (?P<fs>[A-Za-z_$][\w$]*)\.promises\.copyFile"
            r"\((?P<join>[A-Za-z_$][\w$]*)\(__dirname,(?P<name>[A-Za-z_$][\w$]*)\),"
            r"(?P=join)\((?P<directory>[A-Za-z_$][\w$]*),(?P=name)\)\)"
        )
        matches = list(copy_pattern.finditer(source))
        if len(matches) != 2:
            raise SystemExit(
                "Expected the Copilot CLI and debug command shim copies; "
                f"found {len(matches)}"
            )

        shim_declarations = re.findall(
            r"""([A-Za-z_$][\w$]*)\s*=\s*(["'])(copilotCLIShim\.js|copilotDebugCommand\.js)\2""",
            source,
        )
        shim_symbols = {symbol for symbol, _, _ in shim_declarations}
        shim_names = {filename for _, _, filename in shim_declarations}
        if (
            shim_names != {"copilotCLIShim.js", "copilotDebugCommand.js"}
            or {match.group("name") for match in matches} != shim_symbols
        ):
            raise SystemExit(
                "Expected copies of copilotCLIShim.js and copilotDebugCommand.js"
            )

        for match in reversed(matches):
            destination = (
                f"{match.group('join')}("
                f"{match.group('directory')},{match.group('name')})"
            )
            chmod = (
                f"{match.group(0)},await {match.group('fs')}"
                f".promises.chmod({destination},0o644)"
            )
            source = source[:match.start()] + chmod + source[match.end():]
        extension.write_text(source)
        PY
      '';
  });
  rustAnalyzerLauncher = pkgs.writeShellApplication {
    name = "rust-analyzer-project-env";
    runtimeInputs = [pkgs.bash pkgs.coreutils pkgs.direnv];
    text = ''
      fallback='${pkgs.rust-analyzer}/bin/rust-analyzer'
      workspace_dir="$(pwd -P)"
      current_dir="$workspace_dir"
      has_envrc=false

      while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/.envrc" ]]; then
          has_envrc=true
          break
        fi
        current_dir="$(dirname "$current_dir")"
      done

      if [[ "$has_envrc" == true ]] \
        && direnv exec "$workspace_dir" true >/dev/null 2>&1; then
        project_rust_analyzer="$(
          direnv exec "$workspace_dir" bash -c 'command -v rust-analyzer' 2>/dev/null || true
        )"

        if [[ -n "$project_rust_analyzer" && -x "$project_rust_analyzer" ]]; then
          exec direnv exec "$workspace_dir" "$project_rust_analyzer" "$@"
        fi

        exec direnv exec "$workspace_dir" "$fallback" "$@"
      fi

      exec "$fallback" "$@"
    '';
  };
in {
  options.modules.vscode = {
    enable = lib.mkEnableOption "VS Code";

    mutableUserSettings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether Home Manager should seed VS Code settings while leaving
        settings.json writable for imperative edits. Imperative values override
        declarative defaults during activation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.alejandra];

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
      package = vscodePackage;
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

          # Opening a workspace must not silently start unbounded dev/watch
          # tasks. Run approved tasks explicitly from the integrated terminal.
          "task.allowAutomaticTasks" = "off";

          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "nil";
          "nix.formatterPath" = nixFormatter;

          # Prefer the workspace's approved direnv environment so Rust
          # Analyzer, Cargo, and rustc come from the same project dev shell.
          # Fall back to the Nix-managed system binary when no usable .envrc
          # applies; the launcher never approves an environment itself.
          "rust-analyzer.server.path" = "${rustAnalyzerLauncher}/bin/rust-analyzer-project-env";

          "nix.serverSettings" = {
            nil = {
              diagnostics = {
                ignored = [
                  "unused_binding"
                ];
              };

              formatting = {
                command = [nixFormatter];
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

          "biome.lsp.trace.server" = "messages";

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

    # Home Manager normally links settings.json into the Nix store. Keep the
    # declared file as a baseline, then replace the link with a user-owned
    # writable file so VS Code can make imperative edits.
    home.file."${settingsPath}".force = cfg.mutableUserSettings;

    home.activation.vscodeMutableSettingsPrepare = lib.mkIf cfg.mutableUserSettings (
      lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        if [[ ! -v DRY_RUN ]]; then
          settings_file=${lib.escapeShellArg settingsPath}
          staged_file=${lib.escapeShellArg stagedSettingsPath}
          ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$staged_file")"

          if [[ -e "$settings_file" || -L "$settings_file" ]]; then
            ${pkgs.coreutils}/bin/cp -L "$settings_file" "$staged_file"
            if [[ ! -L "$settings_file" ]]; then
              ${pkgs.coreutils}/bin/rm -f "$settings_file"
            fi
          fi
        fi
      ''
    );

    home.activation.vscodeMutableSettingsFinalize = lib.mkIf cfg.mutableUserSettings (
      lib.hm.dag.entryAfter ["linkGeneration"] ''
        if [[ ! -v DRY_RUN ]]; then
          settings_file=${lib.escapeShellArg settingsPath}
          staged_file=${lib.escapeShellArg stagedSettingsPath}
          tmp_file="$(${pkgs.coreutils}/bin/mktemp "$settings_file.tmp.XXXXXX")"

          if [[ -s "$staged_file" ]]; then
            if ${pkgs.jq}/bin/jq -e . "$staged_file" >/dev/null 2>&1; then
              if ! ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings_file" "$staged_file" > "$tmp_file"; then
                ${pkgs.coreutils}/bin/cp -L "$staged_file" "$tmp_file"
              fi
            else
              ${pkgs.coreutils}/bin/cp -L "$staged_file" "$tmp_file"
            fi
          else
            ${pkgs.coreutils}/bin/cp -L "$settings_file" "$tmp_file"
          fi

          ${pkgs.coreutils}/bin/chmod u+rw "$tmp_file"
          ${pkgs.coreutils}/bin/mv -f "$tmp_file" "$settings_file"
          ${pkgs.coreutils}/bin/rm -f "$staged_file"
        fi
      ''
    );

    # ------------------------------------------------------------------
    # IMPORTANT: DO NOT redefine full desktop entries for VS Code
    # Plasma + upstream VS Code already provide correct entries.
    # Overriding them causes duplicate launcher icons.
    # ------------------------------------------------------------------
  };
}

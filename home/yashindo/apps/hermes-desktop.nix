{
  config,
  lib,
  pkgs,
  ...
}: {
  options.modules.hermes-desktop.enable = lib.mkEnableOption "Hermes Desktop";

  config = lib.mkIf config.modules.hermes-desktop.enable (
    let
      computerUseLazyTarget = "${config.home.homeDirectory}/.cache/hermes/computer-use-lazy";
      hermesManagedMarker = "${config.services.hermes-agent.hermesHome}/.managed";

      # Hermes' bootstrap adds the lazy target to sys.path before it imports
      # optional SDKs. A GUI launcher does not inherit shell variables, and the
      # target is loaded from ~/.hermes/.env too late for that bootstrap step.
      # Patch the generated launcher so the value is present at process start.
      desktopPackage = config.programs.hermes-agent.package.hermesDesktop.overrideAttrs (old: {
        postInstall =
          (old.postInstall or "")
          + ''
            python3 - "$out/bin/hermes-desktop" "${computerUseLazyTarget}" <<'PY'
            from pathlib import Path
            import sys

            launcher = Path(sys.argv[1])
            target = sys.argv[2]
            lines = launcher.read_text().splitlines(keepends=True)
            exec_index = next((index for index, line in enumerate(lines) if line.lstrip().startswith("exec ")), None)
            if exec_index is None:
                raise SystemExit("hermes-desktop launcher has no exec boundary")
            lines.insert(exec_index, f"export HERMES_LAZY_INSTALL_TARGET={target!r}\n")
            lines.insert(exec_index, "export CUA_DRIVER_RS_ENABLE_WAYLAND=1\n")
            lines.insert(exec_index, "export ELECTRON_OZONE_PLATFORM_HINT=wayland\n")
            lines.insert(exec_index, "export NIXOS_OZONE_WL=1\n")
            if "--ozone-platform=wayland" not in lines[exec_index + 4]:
                lines[exec_index + 4] = lines[exec_index + 4].replace(
                    ' "$@"', ' --ozone-platform=wayland "$@"', 1
                )
            launcher.write_text("".join(lines))
            PY
          '';
      });
    in {
      services.hermes-agent.extraDependencyGroups = ["computer-use"];

      # The previous Home Manager activation left this marker behind. Remove
      # only the marker so Hermes can manage its existing config.yaml itself.
      home.activation.hermesAgentUnmanagedConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        rm -f ${lib.escapeShellArg hermesManagedMarker}
      '';

      home.sessionVariables = {
        HERMES_LAZY_INSTALL_TARGET = computerUseLazyTarget;
        CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
      };

      # Mnemosyne is an external Python plugin. Its bootstrap currently puts
      # its whole venv at sys.path[0], which exposes a conflicting Starlette
      # pin to Hermes' lazy dependency resolver. Keep the plugin importable,
      # but let Hermes' sealed environment win shared-package collisions.
      home.activation.hermesMnemosynePathOrder = lib.hm.dag.entryAfter ["writeBoundary"] ''
        for plugin in "${config.home.homeDirectory}"/.local/venvs/mnemosyne/lib/python*/site-packages/hermes_memory_provider/*.py; do
          if [[ -f "$plugin" ]]; then
            ${pkgs.python3}/bin/python3 - "$plugin" <<'PY'
        from pathlib import Path
        import sys

        path = Path(sys.argv[1])
        text = path.read_text()
        old = "    sys.path.insert(0, str(_mnemosyne_root))"
        new = "    sys.path.append(str(_mnemosyne_root))"
        if old in text:
            path.write_text(text.replace(old, new, 1))
        elif new not in text:
            sys.exit(0)
        PY
          fi
        done
      '';

      programs.hermes-agent.enable = true;
      programs.hermes-agent.desktop = {
        enable = true;
        package = desktopPackage;
      };
    }
  );
}

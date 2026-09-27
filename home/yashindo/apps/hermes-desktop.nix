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

      # Nix seals the Python environment in /nix/store. Prevent Hermes' service
      # refresh from publishing launchers beside that environment; its service
      # unit can invoke the store Python launcher directly instead.
      hermesCliPackage =
        (config.services.hermes-agent.package.override {
          extraDependencyGroups = config.services.hermes-agent.extraDependencyGroups;
          extraPythonPackages = config.services.hermes-agent.extraPythonPackages;
        }).overrideAttrs (old: {
          postInstall =
            (old.postInstall or "")
            + ''
              launcherShim="$out/lib/hermes-nix-launcher"
              mkdir -p "$launcherShim"
              cat > "$launcherShim/sitecustomize.py" <<'PY'
              import json
              import os
              from pathlib import Path

              try:
                  install_root = Path(os.environ["HERMES_INSTALL_ROOT"]).resolve()
                  stamp = json.loads((install_root / "install-stamp.json").read_text())
              except (KeyError, OSError, ValueError):
                  stamp = {}

              if stamp.get("updateMechanism") == "external" and Path("/nix/store") in install_root.parents:
                  from hermes_cli import _launchers, venv_sync

                  _launchers.resolve_store_python = lambda _repo_root: None
                  venv_sync.check_runtime = lambda _project_root: None
              PY

              for command in hermes hermes-agent hermes-acp; do
                if [ -x "$out/bin/$command" ]; then
                  mv "$out/bin/$command" "$out/bin/$command-unwrapped"
                  makeWrapper "$out/bin/$command-unwrapped" "$out/bin/$command" --prefix PYTHONPATH : "$launcherShim"
                fi
              done
            '';
        });

      # Hermes' bootstrap adds the lazy target to sys.path before it imports
      # optional SDKs. A GUI launcher does not inherit shell variables, and the
      # target is loaded from ~/.hermes/.env too late for that bootstrap step.
      # Patch the generated launcher so the value is present at process start.
      desktopPackage = hermesCliPackage.hermesDesktop.overrideAttrs (old: {
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
            # The desktop app routes ANGLE through SwiftShader as soon as the
            # NVIDIA driver major is >= 580 (upstream #40077), which disables
            # hardware acceleration entirely. This host is a hybrid AMD iGPU +
            # NVIDIA 615 machine, so that guard fires on every launch and the
            # GPU process software-rasterises the whole UI. Chromium already
            # composites on the AMD render node here, so opt out and keep the
            # launcher on hardware acceleration. Set this to 1 to restore the
            # SwiftShader fallback if the GPU process crashes.
            exec_index = next(
                index for index, line in enumerate(lines) if line.lstrip().startswith("exec ")
            )
            lines.insert(exec_index, "export HERMES_DESKTOP_NVIDIA_SWIFTSHADER=0\n")
            # Request NVIDIA PRIME offload for Hermes' Electron process.
            exec_index = next(
                index for index, line in enumerate(lines) if line.lstrip().startswith("exec ")
            )
            if "exec nvidia-offload " not in lines[exec_index]:
                lines[exec_index] = lines[exec_index].replace(
                    "exec ", "exec nvidia-offload ", 1
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
      programs.hermes-agent.package = hermesCliPackage;
      programs.hermes-agent.desktop = {
        enable = true;
        package = desktopPackage;
      };
    }
  );
}

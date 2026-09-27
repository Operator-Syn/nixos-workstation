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
      cuaDriverPath = "${config.home.homeDirectory}/.local/bin/cua-driver";
      browserCdpProfile = "${config.home.homeDirectory}/.local/share/hermes-cdp-profile";
      browserCdpUrl = "http://127.0.0.1:9222";
      browserCdpLauncher = pkgs.writeShellScriptBin "hermes-cdp-browser" ''
        set -euo pipefail
        install -d -m 0700 ${lib.escapeShellArg browserCdpProfile}
        exec ${pkgs.google-chrome}/bin/google-chrome-stable \
          --user-data-dir=${lib.escapeShellArg browserCdpProfile} \
          --remote-debugging-address=127.0.0.1 \
          --remote-debugging-port=9222 \
          --no-first-run \
          "$@"
      '';
      hermesManagedMarker = "${config.services.hermes-agent.hermesHome}/.managed";

      # Nix seals the Python environment in /nix/store. Put the managed-runtime
      # compatibility hooks in site-packages so they also load for Hermes'
      # isolated `python -I` service-action subprocesses.
      hermesBasePackage = config.services.hermes-agent.package.override {
        extraDependencyGroups = config.services.hermes-agent.extraDependencyGroups;
        extraPythonPackages = config.services.hermes-agent.extraPythonPackages;
      };
      hermesSitecustomize = pkgs.writeText "hermes-sitecustomize.py" ''
        import sys

        from hermes_cli import _launchers, venv_sync

        _launchers.resolve_store_python = lambda _repo_root: None
        venv_sync.check_runtime = lambda _project_root: None

        if "doctor" in sys.argv[1:]:
            try:
                from hermes_cli import doctor_tools
                from tools.browser_use_cli import get_browser_backend

                if get_browser_backend() == "off":
                    _check_warn = doctor_tools.check_warn

                    def _doctor_mode_check_warn(label, *args, **kwargs):
                        if label == "browser-use":
                            return doctor_tools.check_info("browser-use (inactive: built-in browser/CDP selected)")
                        return _check_warn(label, *args, **kwargs)

                    doctor_tools.check_warn = _doctor_mode_check_warn
            except Exception:
                pass
      '';
      hermesPythonEnv = hermesBasePackage.hermesVenv.overrideAttrs (old: {
        postFixup =
          (old.postFixup or "")
          + ''
            install -m 0444 ${hermesSitecustomize} "$out/${hermesBasePackage.python.sitePackages}/sitecustomize.py"
          '';
      });
      hermesAgentInputs = pkgs.writeText "hermes-agent-inputs.json" (
        builtins.replaceStrings
        [(toString hermesBasePackage.hermesVenv)]
        [(toString hermesPythonEnv)]
        (builtins.readFile hermesBasePackage.agentInputsFile)
      );
      hermesCliPackage = hermesBasePackage.overrideAttrs (old: {
        installPhase =
          builtins.replaceStrings
          [
            (toString hermesBasePackage.agentInputsFile)
            (toString hermesBasePackage.hermesVenv)
          ]
          [
            (toString hermesAgentInputs)
            (toString hermesPythonEnv)
          ]
          old.installPhase;
        passthru =
          (old.passthru or {})
          // {
            hermesVenv = hermesPythonEnv;
            agentInputsFile = hermesAgentInputs;
          };
      });

      # Patch only the packaged renderer. The upstream flake input stays
      # pinned and its source remains untouched.
      desktopRendererPatch = pkgs.writeText "hermes-desktop-transcript.patch" ''
        --- a/apps/desktop/src/app/session/hooks/use-message-stream/index.ts
        +++ b/apps/desktop/src/app/session/hooks/use-message-stream/index.ts
        @@ -119,10 +119,36 @@
        -          const reconciledId = opts.eventTarget?.(state) ?? null
        -          const streamId = reconciledId ?? state.streamId ?? nextStreamMessageId('assistant-stream')
        -          // The event landed on a bubble that is NOT the live stream (sealed
        -          // by interim commentary, a mid-turn user message, or turn settle).
        -          // It is a patch to history: the bubble keeps its own pending bit
        -          // and the turn's stream bookkeeping is neither consulted nor changed.
        -          const patchesSealedBubble = reconciledId !== null && reconciledId !== state.streamId
        -          const groupId = state.pendingBranchGroup ?? undefined
        -          const prev = state.messages
        -          let nextMessages: ChatMessage[]
        +          const reconciledId = opts.eventTarget?.(state) ?? null
        +          // The event landed on a bubble that is NOT the live stream (sealed
        +          // by interim commentary, a mid-turn user message, or turn settle).
        +          // It is a patch to history: the bubble keeps its own pending bit
        +          // and the turn's stream bookkeeping is neither consulted nor changed.
        +          const patchesSealedBubble = reconciledId !== null && reconciledId !== state.streamId
        +          const groupId = state.pendingBranchGroup ?? undefined
        +          const prev = state.messages
        +          const lastUserIndex = prev.findLastIndex(message => message.role === 'user')
        +          const requestedStreamId = reconciledId ?? state.streamId
        +          const requestedStreamExists =
        +            requestedStreamId !== null && prev.some(message => message.id === requestedStreamId)
        +          // A transcript refresh can replace the live bubble while leaving
        +          // streamId pointed at its old local id. Reattach deltas to the live
        +          // tail after the latest user instead of seeding a duplicate bubble.
        +          const recoverableStreamId =
        +            !reconciledId && state.busy && state.awaitingResponse
        +              ? prev.findLast(
        +                  (message, index) =>
        +                    index > lastUserIndex &&
        +                    message.role === 'assistant' &&
        +                    !message.hidden &&
        +                    !message.interim &&
        +                    !message.error &&
        +                    (message.pending === true ||
        +                      message.durableComplete === false ||
        +                      message.persistedTurn?.complete === false ||
        +                      message.id.startsWith('assistant-stream-') ||
        +                      message.id.startsWith('inflight-assistant-'))
        +                )?.id ?? null
        +              : null
        +          const streamId =
        +            reconciledId ??
        +            (requestedStreamExists ? requestedStreamId : recoverableStreamId) ??
        +            nextStreamMessageId('assistant-stream')
        +          let nextMessages: ChatMessage[]
        --- a/apps/desktop/src/app/session/hooks/use-prompt-actions/submit.ts
        +++ b/apps/desktop/src/app/session/hooks/use-prompt-actions/submit.ts
        @@ -44,1 +44,1 @@
        -import { resolveSessionProfile } from '../use-session-actions/utils'
        +import { preserveLocalPendingTurnMessages, resolveSessionProfile } from '../use-session-actions/utils'
        @@ -846,26 +846,28 @@
        -          if (refreshed) {
        -            updateSessionState(
        -              liveSessionId,
        -              state => ({
        -                ...state,
        -                awaitingResponse: false,
        -                busy: false,
        -                messages: refreshed,
        -                pendingBranchGroup: null
        -              }),
        -              targetStoredSessionId
        -            )
        -
        -            if (targetIsCurrentView()) {
        -              scope.setMessages(() => refreshed)
        -              notify({
        -                kind: 'warning',
        -                message: copy.staleSessionBody,
        -                title: copy.staleSessionTitle
        -              })
        -            }
        -
        -            releaseBusy()
        -
        -            return false
        -          }
        +          if (refreshed) {
        +            // The freshness read runs before prompt.submit, so this send is
        +            // still uncommitted. Rebase the live transcript and optimistic
        +            // user row, then continue with this same submission.
        +            const rebasedState = updateSessionState(
        +              liveSessionId,
        +              state => {
        +                const optimisticMessage = state.messages.find(
        +                  message => message.id === optimisticId && message.role === 'user'
        +                )
        +                const rebasedMessages = preserveLocalPendingTurnMessages(
        +                  refreshed,
        +                  state.messages.filter(message => message.id !== optimisticId)
        +                ).filter(message => message.id !== optimisticId)
        +
        +                return {
        +                  ...state,
        +                  messages: optimisticMessage ? [...rebasedMessages, optimisticMessage] : rebasedMessages,
        +                  pendingBranchGroup: null
        +                }
        +              },
        +              targetStoredSessionId
        +            )
        +
        +            if (targetIsCurrentView()) {
        +              scope.setMessages(() => rebasedState.messages)
        +            }
        +          }
      '';
      hermesDesktopNpmLib =
        hermesCliPackage.hermesNpmLib
        // {
          buildNpmPackage = args:
            hermesCliPackage.hermesNpmLib.buildNpmPackage (
              if (args.pname or null) == "hermes-desktop-renderer"
              then args // {patches = (args.patches or []) ++ [desktopRendererPatch];}
              else args
            );
        };

      # Hermes' bootstrap adds the lazy target to sys.path before it imports
      # optional SDKs. A GUI launcher does not inherit shell variables, and the
      # target is loaded from ~/.hermes/.env too late for that bootstrap step.
      # Patch the generated launcher so the value is present at process start.
      desktopHermesPackage = hermesCliPackage.hermesDesktop.override {
        hermesNpmLib = hermesDesktopNpmLib;
      };
      desktopPackage = desktopHermesPackage.overrideAttrs (old: {
        postInstall =
          (old.postInstall or "")
          + ''
            python3 - "$out/bin/hermes-desktop" "${computerUseLazyTarget}" "${cuaDriverPath}" "${browserCdpUrl}" <<'PY'
            from pathlib import Path
            import sys

            launcher = Path(sys.argv[1])
            target = sys.argv[2]
            cua_driver = sys.argv[3]
            browser_cdp_url = sys.argv[4]
            lines = launcher.read_text().splitlines(keepends=True)
            exec_index = next((index for index, line in enumerate(lines) if line.lstrip().startswith("exec ")), None)
            if exec_index is None:
                raise SystemExit("hermes-desktop launcher has no exec boundary")
            environment = [
                f"export HERMES_LAZY_INSTALL_TARGET={target!r}\n",
                "export CUA_DRIVER_RS_ENABLE_WAYLAND=1\n",
                f"export HERMES_CUA_DRIVER_CMD={cua_driver!r}\n",
                f"export BROWSER_CDP_URL={browser_cdp_url!r}\n",
                "export A2A_HOST=127.0.0.1\n",
                "export A2A_PORT=9900\n",
                "export ELECTRON_OZONE_PLATFORM_HINT=wayland\n",
                "export NIXOS_OZONE_WL=1\n",
                "export HERMES_DESKTOP_NVIDIA_SWIFTSHADER=0\n",
            ]
            lines[exec_index:exec_index] = environment
            exec_index += len(environment)
            if "--ozone-platform=wayland" not in lines[exec_index]:
                lines[exec_index] = lines[exec_index].replace(
                    ' "$@"', ' --ozone-platform=wayland "$@"', 1
                )
            # Leave GPU selection and NVIDIA/ANGLE fallback to Hermes Desktop.
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

      home.packages = [browserCdpLauncher];

      xdg.desktopEntries.hermes-cdp-browser = {
        name = "Hermes Browser (CDP)";
        genericName = "Dedicated browser profile for Hermes";
        comment = "Launch the isolated browser profile used by Hermes agents";
        exec = "${browserCdpLauncher}/bin/hermes-cdp-browser";
        icon = "google-chrome";
        terminal = false;
        categories = ["Network" "WebBrowser"];
      };

      home.sessionVariables = {
        HERMES_LAZY_INSTALL_TARGET = computerUseLazyTarget;
        CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
        HERMES_CUA_DRIVER_CMD = cuaDriverPath;
        BROWSER_CDP_URL = browserCdpUrl;
        A2A_HOST = "127.0.0.1";
        A2A_PORT = "9900";
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

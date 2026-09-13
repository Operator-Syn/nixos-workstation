{
  config,
  pkgs,
  lib,
  pkgsUnstable,
  ...
}: let
  # Obsidian's Linux CLI checks the executable name of the running desktop
  # process. The nixpkgs launcher ultimately execs Electron, so that check sees
  # "electron" and refuses CLI registration. Keep the same packaged app, but
  # provide an Electron executable named "obsidian" for the private GUI runtime.
  obsidianBase = pkgsUnstable.obsidian;
  obsidian = pkgsUnstable.runCommand "obsidian-fixed-${obsidianBase.version}" {} ''
    cp -a ${obsidianBase}/. "$out/"
    chmod -R u+w "$out"

    mkdir -p "$out/libexec/obsidian"
    cp -a ${pkgsUnstable.electron.unwrapped}/libexec/electron/. "$out/libexec/obsidian/"
    chmod -R u+w "$out/libexec/obsidian"
    cp "$out/libexec/obsidian/electron" "$out/libexec/obsidian/obsidian"
    rm "$out/libexec/obsidian/electron"

    # Do not expose the private GUI executable as the user-facing "obsidian"
    # command; that name is reserved for the CLI wrapper below.
    rm -f "$out/bin/obsidian"
    rm -f "$out/share/applications/obsidian.desktop"
  '';

  obsidianCli = pkgsUnstable.writeShellScriptBin "obsidian" ''
    exec "${obsidian}/bin/obsidian-cli" "$@"
  '';

  obsidianDesktop = pkgsUnstable.writeShellScriptBin "obsidian-desktop" ''
    # Electron-hosted shells can export these variables and make the GUI start
    # in Node mode instead of loading Obsidian.
    unset ELECTRON_RUN_AS_NODE
    unset ELECTRON_NO_ATTACH_CONSOLE

    export CHROME_DEVEL_SANDBOX="${obsidian}/libexec/obsidian/chrome-sandbox"

    ozone_args=()
    if test -n "''${NIXOS_OZONE_WL:-}" && test -n "''${WAYLAND_DISPLAY:-}"; then
      ozone_args=(
        --ozone-platform=wayland
        --enable-wayland-ime=true
        --wayland-text-input-version=3
      )
    fi

    exec "${obsidian}/libexec/obsidian/obsidian" \
      "${obsidian}/share/obsidian/app.asar" \
      "''${ozone_args[@]}" \
      "$@"
  '';
in {
  options.modules.obsidian.enable = lib.mkEnableOption "Obsidian";

  config = lib.mkIf config.modules.obsidian.enable {
    # Keep the runtime in the profile for its icon and CLI assets, but expose
    # only the explicit CLI and desktop command names.
    home.packages = [
      obsidian
      obsidianCli
      obsidianDesktop
    ];

    # Obsidian's documented Linux registration target. Keep this as a
    # writable copy so Obsidian can refresh it when Register CLI is clicked.
    home.activation.obsidianCli = lib.hm.dag.entryAfter ["writeBoundary"] ''
      cli_dir="${config.home.homeDirectory}/.local/bin"
      cli="$cli_dir/obsidian"
      $DRY_RUN_CMD ${pkgsUnstable.coreutils}/bin/mkdir -p "$cli_dir"

      if test -L "$cli"; then
        $DRY_RUN_CMD ${pkgsUnstable.coreutils}/bin/rm "$cli"
      fi

      $DRY_RUN_CMD ${pkgsUnstable.coreutils}/bin/install -m 755 \
        "${obsidian}/bin/obsidian-cli" "$cli"
    '';

    # Keep the mutable Obsidian state aligned with the Nix-pinned runtime when
    # it is safe to do so. If the desktop is open, defer the rewrite until a
    # later activation instead of failing the entire Home Manager generation.
    home.activation.obsidianNixPin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [[ ! -v DRY_RUN ]]; then
        obsidian_dir="${config.home.homeDirectory}/.config/obsidian"
        obsidian_state="$obsidian_dir/obsidian.json"

        if ${pkgs.procps}/bin/pgrep -u "$USER" -x obsidian >/dev/null 2>&1; then
          echo "Obsidian is running; deferring state synchronization." >&2
        else
          obsidian_runtime="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
          obsidian_socket="$obsidian_runtime/.obsidian-cli.sock"
          if [[ -S "$obsidian_socket" ]]; then
            ${pkgs.coreutils}/bin/unlink "$obsidian_socket"
          fi

          ${pkgs.coreutils}/bin/mkdir -p "$obsidian_dir"

          if [[ -L "$obsidian_state" ]]; then
            echo "Refusing to replace symlinked Obsidian state: $obsidian_state" >&2
            exit 1
          fi

          tmp_file="$(${pkgs.coreutils}/bin/mktemp "$obsidian_state.tmp.XXXXXX")"
          trap '${pkgs.coreutils}/bin/rm -f "$tmp_file"' EXIT

          if [[ -e "$obsidian_state" ]]; then
            if ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$obsidian_state" >/dev/null 2>&1; then
              echo "Obsidian state is not a valid JSON object: $obsidian_state" >&2
              exit 1
            fi

            ${pkgs.jq}/bin/jq '. + {"updateDisabled": true}' "$obsidian_state" > "$tmp_file"
            ${pkgs.coreutils}/bin/chmod --reference="$obsidian_state" "$tmp_file"
          else
            ${pkgs.coreutils}/bin/printf '%s\n' '{"updateDisabled":true}' > "$tmp_file"
            ${pkgs.coreutils}/bin/chmod 600 "$tmp_file"
          fi

          ${pkgs.coreutils}/bin/mv -f "$tmp_file" "$obsidian_state"
          trap - EXIT

          for asar in "$obsidian_dir"/obsidian-*.asar; do
            if [[ -f "$asar" ]]; then
              echo "Removing Obsidian updater artifact: $asar"
              ${pkgs.coreutils}/bin/rm -f "$asar"
            fi
          done
        fi
      fi
    '';

    home.sessionPath = ["${config.home.homeDirectory}/.local/bin"];

    home.file.".local/share/applications/obsidian.desktop".text = ''
      [Desktop Entry]
      Name=Obsidian
      Comment=Knowledge base
      Exec=${obsidianDesktop}/bin/obsidian-desktop %u
      TryExec=${obsidianDesktop}/bin/obsidian-desktop
      Icon=obsidian
      Type=Application
      Categories=Office;
      MimeType=x-scheme-handler/obsidian;
      StartupWMClass=md.Obsidian
      Terminal=false
    '';

    # The CLI bridge needs the desktop application to be running. Start the
    # direct GUI launcher at KDE login; the KWin rule keeps it minimized while
    # leaving a normal taskbar entry available for restoring the window.
    xdg.configFile."autostart/obsidian.desktop".text = ''
      [Desktop Entry]
      Name=Obsidian CLI bridge
      Comment=Start Obsidian for CLI commands
      Exec=${obsidianDesktop}/bin/obsidian-desktop
      TryExec=${obsidianDesktop}/bin/obsidian-desktop
      Type=Application
      Categories=Office;
      OnlyShowIn=KDE;
      X-GNOME-Autostart-enabled=true
    '';
  };
}

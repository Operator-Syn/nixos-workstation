{
  config,
  lib,
  pkgsUnstable,
  ...
}: let
  # Obsidian's Linux CLI checks the executable name of the running desktop
  # process.  The nixpkgs launcher ultimately execs Electron, so that check
  # sees "electron" and refuses CLI registration.  Keep the same packaged
  # app, but provide an Electron executable named "obsidian" for the GUI.
  obsidianBase = pkgsUnstable.obsidian;
  obsidian = pkgsUnstable.runCommand "obsidian-fixed-${obsidianBase.version}" {} ''
    cp -a ${obsidianBase}/. "$out/"
    chmod -R u+w "$out"

    mkdir -p "$out/libexec/obsidian"
    cp -a ${pkgsUnstable.electron.unwrapped}/libexec/electron/. "$out/libexec/obsidian/"
    chmod -R u+w "$out/libexec/obsidian"
    cp "$out/libexec/obsidian/electron" "$out/libexec/obsidian/obsidian"
    rm "$out/libexec/obsidian/electron"
    rm -f "$out/share/applications/obsidian.desktop"
  '';

  obsidianDesktop = pkgsUnstable.writeShellScriptBin "obsidian-desktop" ''
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
    home.packages = [
      obsidian
      obsidianDesktop
    ];

    # Obsidian's documented Linux registration target.  Keep this as a
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
    '';
  };
}

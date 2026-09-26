{
  config,
  lib,
  pkgs,
  ...
}: let
  desktopEntryName = "plasma-manager-commands";
  shortcutFile = "${config.xdg.configHome}/kglobalshortcutsrc";
  kconfig = pkgs.kdePackages.kconfig;
  missingValue = "__nix_config_shortcut_missing__";
in {
  # Installed under XDG_DATA_HOME/kglobalaccel, which is where KGlobalAccelD
  # discovers service components (it scans <data dir>/kglobalaccel/*.desktop and
  # maps each file's Actions to shortcut actions). xdg.desktopEntries was wrong
  # here twice over: it publishes the file into share/applications as a profile
  # package, which KGlobalAccelD does not read for actions, and it is only
  # reachable when ~/.nix-profile exposes it. This path is scanned first and is
  # the same mechanism Spectacle, Dolphin and Konsole use.
  home.file.".local/share/kglobalaccel/${desktopEntryName}.desktop".text = ''
    [Desktop Entry]
    Actions=open-alacritty;camera-privacy
    Name=Plasma starter shortcuts
    NoDisplay=true
    StartupNotify=false
    Terminal=false
    Type=Application
    Version=1.5

    [Desktop Action open-alacritty]
    Name=Open Alacritty
    Exec=${pkgs.alacritty-graphics}/bin/alacritty

    [Desktop Action camera-privacy]
    Name=Toggle webcam privacy
    Exec=/run/current-system/sw/bin/camera-privacy toggle
  '';
  # The camera action targets a command provided system-wide by
  # modules/nixos/desktop/camera-privacy.nix; it only exists once that system
  # generation is activated.

  # Do not use programs.plasma.hotkeys here: that module intentionally rewrites
  # declared keys on every activation. These bindings are one-time defaults,
  # after which kglobalshortcutsrc is owned by Plasma and the user.
  home.activation.seedPlasmaStarterShortcuts = lib.hm.dag.entryAfter ["writeBoundary"] ''
    shortcut_file=${lib.escapeShellArg shortcutFile}
    kreadconfig=${kconfig}/bin/kreadconfig6
    kwriteconfig=${kconfig}/bin/kwriteconfig6
    shortcut_group=${lib.escapeShellArg desktopEntryName}
    missing_value=${lib.escapeShellArg missingValue}

    seed_shortcut() {
      action="$1"
      key="$2"

      if [ "$($kreadconfig \
        --file "$shortcut_file" \
        --group services \
        --group "''${shortcut_group}.desktop" \
        --key "$action" \
        --default "$missing_value")" = "$missing_value" ]; then
        $DRY_RUN_CMD "$kwriteconfig" \
          --file "$shortcut_file" \
          --group services \
          --group "''${shortcut_group}.desktop" \
          --key "$action" \
          "$key"
      fi
    }

    seed_shortcut open-alacritty Ctrl+Shift+X
    seed_shortcut camera-privacy Meta+Shift+C
  '';
}

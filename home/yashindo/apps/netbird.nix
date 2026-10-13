{
  config,
  lib,
  pkgsUnstable,
  ...
}: let
  netbirdUi = pkgsUnstable.netbird-ui.overrideAttrs (finalAttrs: previousAttrs: {
    # NetBird/Wails requests Plasma's default expiration (-1). Pin this UI's
    # Linux notifications to three seconds without changing other applications.
    proxyVendor = false;
    vendorHash = "sha256-yIQCKamEEw6sG2x6lZgoTupFJzcDqCJYYBzf1h/7ozA=";
    modPostBuild =
      (previousAttrs.modPostBuild or "")
      + ''
        substituteInPlace vendor/github.com/wailsapp/wails/v3/pkg/services/notifications/notifications_linux.go \
          --replace-fail 'int32(-1),' 'int32(3000),'
      '';
  });
in {
  options.modules.netbird.enable = lib.mkEnableOption "NetBird tray application";

  config = lib.mkIf config.modules.netbird.enable {
    home.packages = [netbirdUi];

    # Reuse the desktop entry packaged with NetBird so Exec and icon metadata
    # stay aligned with the UI version. Plasma launches it with the user session.
    home.file.".config/autostart/netbird.desktop".source = "${netbirdUi}/share/applications/netbird.desktop";
  };
}

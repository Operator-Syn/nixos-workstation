{
  config,
  lib,
  pkgsUnstable,
  ...
}: {
  options.modules.netbird.enable = lib.mkEnableOption "NetBird VPN client";

  config = lib.mkIf config.modules.netbird.enable {
    services.netbird = {
      enable = true;
      package = pkgsUnstable.netbird;
    };

    # Use NetBird's documented fallback for Linux exit-node routing issues.
    systemd.services.netbird.environment.NB_USE_LEGACY_ROUTING = "true";

    environment.systemPackages = [
      pkgsUnstable.netbird
    ];
  };
}

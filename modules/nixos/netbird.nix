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

    environment.systemPackages = [
      pkgsUnstable.netbird
    ];
  };
}

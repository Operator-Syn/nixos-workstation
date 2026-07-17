{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.steam.protontricks.enable =
    lib.mkEnableOption "Protontricks support";

  config = lib.mkIf (config.modules.steam.enable && config.modules.steam.protontricks.enable) {
    environment.systemPackages = [pkgs.protontricks];
  };
}

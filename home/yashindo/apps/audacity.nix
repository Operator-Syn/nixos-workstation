{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.audacity.enable = lib.mkEnableOption "Audacity";

  config = lib.mkIf config.modules.audacity.enable {
    home.packages = with pkgs; [
      audacity
    ];
  };
}

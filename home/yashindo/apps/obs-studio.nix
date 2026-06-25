{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.obs-studio.enable = lib.mkEnableOption "OBS Studio";

  config = lib.mkIf config.modules.obs-studio.enable {
    home.packages = with pkgs; [
      obs-studio
    ];
  };
}

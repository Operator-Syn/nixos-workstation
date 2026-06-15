{
  lib,
  config,
  ...
}: {
  options.modules.easyeffects.enable =
    lib.mkEnableOption "EasyEffects";

  config = lib.mkIf config.modules.easyeffects.enable {
    services.easyeffects.enable = true;
  };
}

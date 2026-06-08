{
  config,
  lib,
  pkgsUnstable,
  ...
}: {
  options.modules.winboat.enable = lib.mkEnableOption "WinBoat Windows app runner";

  config = lib.mkIf config.modules.winboat.enable {
    home.packages = [pkgsUnstable.winboat];
  };
}

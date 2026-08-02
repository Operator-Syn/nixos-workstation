{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.blender.enable = lib.mkEnableOption "Blender 3D content creation";

  config = lib.mkIf config.modules.blender.enable {
    home.packages = with pkgs; [
      blender
    ];
  };
}

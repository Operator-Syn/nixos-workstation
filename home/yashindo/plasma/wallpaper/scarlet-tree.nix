{
  config,
  lib,
  ...
}: {
  options.modules.scarlet-tree.enable = lib.mkEnableOption "Scarlet Tree wallpaper";
  config = lib.mkIf config.modules.scarlet-tree.enable {
    programs.plasma.workspace = {
      wallpaper = "/run/current-system/sw/share/wallpapers/ScarletTree";
      wallpaperFillMode = "preserveAspectCrop";
    };
  };
}

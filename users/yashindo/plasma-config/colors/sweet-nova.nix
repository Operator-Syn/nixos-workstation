{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.sweetNova;
in {
  options.modules.sweetNova = {
    enable = mkEnableOption "Enable Sweet Nova color scheme with dynamic accent";
  };

  config = mkIf cfg.enable {
    # Install the theme package
    home.packages = [pkgs.sweet-nova];

    programs.plasma = {
      enable = true;

      # Set the base color scheme
      workspace.colorScheme = "Sweet";

      # Force the Accent Color to follow the wallpaper
      # This mimics the "Accent Color from Wallpaper" toggle in System Settings
      configFile."kdeglobals"."General" = {
        "accentColorFromWallpaper" = true;
      };
    };
  };
}

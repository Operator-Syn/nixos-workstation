{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.candyIcons;
in {
  options.modules.candyIcons = {
    enable = mkEnableOption "Enable Candy Icons and set as Plasma icon theme";
  };

  config = mkIf cfg.enable {
    home.packages = [pkgs.candy-icons];

    programs.plasma = {
      enable = true;
      workspace = {
        iconTheme = "candy-icons";
      };
    };
  };
}

{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.libreoffice.enable = lib.mkEnableOption "LibreOffice";

  config = lib.mkIf config.modules.libreoffice.enable {
    home.packages = [pkgs.libreoffice-qt6];
  };
}

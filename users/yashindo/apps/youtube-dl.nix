{
  config,
  pkgs,
  lib,
  ...
}: {
  options.modules.youtube-dl.enable = lib.mkEnableOption "youtube-dl";

  config = lib.mkIf config.modules.youtube-dl.enable {
    home.packages = [pkgs.python312Packages.yt-dlp];
  };
}

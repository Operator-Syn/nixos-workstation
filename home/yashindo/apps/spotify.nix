{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.spotify.enable = lib.mkEnableOption "Spotify";

  config = lib.mkIf config.modules.spotify.enable {
    home.packages = [pkgs.spotify];
  };
}

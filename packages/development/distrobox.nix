{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.modules.distrobox;
in {
  options.modules.distrobox.enable =
    lib.mkEnableOption "Distrobox container support";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      distrobox
    ];

    environment.variables = {
      DISTROBOX_CONTAINER_MANAGER = "docker";
    };
  };
}

{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.modules.distrobox.debian-dev;

  assembleDebianDev = pkgs.writeShellScriptBin "assemble-debian-dev" ''
    exec ${pkgs.distrobox}/bin/distrobox assemble create \
      --file /etc/distrobox/debian-dev.ini \
      --name debian-dev \
      "$@"
  '';
in {
  options.modules.distrobox.debian-dev.enable =
    lib.mkEnableOption "Debian Distrobox development container";

  config = lib.mkIf cfg.enable {
    modules.distrobox.enable = true;

    environment.systemPackages = [
      assembleDebianDev
    ];

    environment.etc."distrobox/debian-dev.ini".text = ''
      [debian-dev]
      image=debian:bookworm
      home=/home/yashindo/distrobox/debian-dev-home
      additional_packages="git curl wget vim build-essential ca-certificates sudo locales"
      pre_init_hooks="export SHELL=/bin/bash;"
      init=false
      nvidia=false
      pull=true
      root=false
      replace=false
      start_now=false
    '';
  };
}

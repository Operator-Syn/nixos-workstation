{ config, lib, ... }:
let
  cfg = config.hostStorage;
in
{
  options.hostStorage.enable = lib.mkEnableOption "the secondary M.2 SSD mount";

  config = lib.mkIf cfg.enable {
    fileSystems."/mnt/storage" = {
      device = "/dev/disk/by-uuid/68eaa544-b6d9-4928-ab3a-959d2e2890e3";
      fsType = "ext4";
      options = [ "nofail" ];
    };

    systemd.tmpfiles.rules = [
      "d /mnt/storage 0777 root root -"
    ];
  };
}

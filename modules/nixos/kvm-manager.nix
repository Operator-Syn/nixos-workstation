{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.kvm-manager;
in {
  options.modules.kvm-manager.enable =
    lib.mkEnableOption "KVM virtual machine manager support";

  config = lib.mkIf cfg.enable {
    programs.virt-manager.enable = true;

    virtualisation.libvirtd = {
      enable = true;

      qemu = {
        package = pkgs.qemu_kvm;
        swtpm.enable = true;
      };
    };
  };
}

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

    systemd.services.libvirt-default-network = {
      description = "Start the default libvirt network";
      wantedBy = ["multi-user.target"];
      wants = ["libvirtd.service"];
      after = ["libvirtd.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.libvirt}/bin/virsh -c qemu:///system net-autostart default
        if ! ${pkgs.libvirt}/bin/virsh -c qemu:///system net-info default | ${pkgs.gnugrep}/bin/grep -q 'Active:.*yes'; then
          ${pkgs.libvirt}/bin/virsh -c qemu:///system net-start default
        fi
      '';
    };
  };
}

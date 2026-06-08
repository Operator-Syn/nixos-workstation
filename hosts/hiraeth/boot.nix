{pkgs, ...}: {
  boot = {
    kernelPackages = pkgs.linuxPackages_zen;

    loader = {
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        useOSProber = true;
      };

      systemd-boot.enable = false;

      efi.canTouchEfiVariables = true;
    };
  };
}

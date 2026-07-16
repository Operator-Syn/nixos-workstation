{pkgsUnstable, ...}: {
  boot = {
    # ASUS Armoury support is provided by the newer kernel package set.
    # NVIDIA is configured with open kernel modules in nvidia.nix so both
    # drivers are available in the same generation.
    kernelPackages = pkgsUnstable.linuxPackages_latest;

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

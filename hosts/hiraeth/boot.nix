{pkgsUnstable, ...}: {
  boot = {
    # ASUS Armoury support is provided by the newer kernel package set.
    # NVIDIA is configured with open kernel modules in nvidia.nix so both
    # drivers are available in the same generation.
    kernelPackages = pkgsUnstable.linuxPackages_latest;

    # Tune memory reclaim. The default swappiness (60) proactively swaps live
    # anonymous memory into zram even with free RAM, causing intermittent lag
    # when swapped pages are faulted back in. Lower it so the kernel reclaims
    # only under genuine pressure, and keep the file cache (fast NVMe reads)
    # instead of evicting it.
    kernel.sysctl = {
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
    };

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

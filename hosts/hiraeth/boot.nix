{pkgsUnstable, ...}: {
  boot = {
    # ASUS Armoury support is provided by the newer kernel package set.
    # NVIDIA is configured with open kernel modules in nvidia.nix so both
    # drivers are available in the same generation.
    kernelPackages = pkgsUnstable.linuxPackages;

    kernelModules = ["ntsync"];

    # Keep the RTL8852BE AP path out of its low-power and PCIe link-power
    # states; those states cause rtw89 queue flush failures during hotspot use.
    extraModprobeConfig = ''
      options rtw89_core disable_ps_mode=Y
      options rtw89_pci disable_aspm_l1=Y disable_aspm_l1ss=Y disable_clkreq=Y
    '';

    # Prefer earlier compressed reclaim so zram absorbs pressure before the
    # desktop stalls on reclaim faults, while keeping file cache priority.
    kernel.sysctl = {
      "vm.swappiness" = 100;
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

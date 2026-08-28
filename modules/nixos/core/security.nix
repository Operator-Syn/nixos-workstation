{
  security = {
    polkit.enable = true;

    sudo = {
      enable = true;
      extraConfig = ''
        Defaults pwfeedback
      '';
    };
  };

  # Monitor the top-level user.slice before the kernel reaches a global OOM.
  # enableUserSlices opts user-owned slices into oomd at NixOS's 80% default;
  # this host lowers only the top-level limit to 60% and keeps the 30s duration.
  systemd.oomd = {
    enable = true;
    enableUserSlices = true;
  };

  systemd.slices.user.sliceConfig.ManagedOOMMemoryPressureLimit = "60%";

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
}

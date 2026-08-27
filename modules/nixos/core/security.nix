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

  # Monitor user-owned slices before the kernel reaches a global OOM. The
  # default systemd-oomd service is enabled by NixOS, but it does not manage
  # user slices unless this option is enabled.
  systemd.oomd = {
    enable = true;
    enableUserSlices = true;
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
}

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

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
}

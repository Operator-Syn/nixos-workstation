{
  programs.dconf.enable = true;
  programs.firefox.enable = true;

  security.rtkit.enable = true;

  services = {
    desktopManager.plasma6.enable = true;
    displayManager.sddm.enable = true;
    printing.enable = true;
    pulseaudio.enable = false;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };
}

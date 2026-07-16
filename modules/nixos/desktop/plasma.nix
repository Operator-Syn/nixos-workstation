{pkgs, ...}: {
  programs.dconf.enable = true;
  programs.firefox = {
    enable = true;
    package = pkgs.firefox-esr;
  };

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
  ];

  security.rtkit.enable = true;

  # Plasma exposes this D-Bus service in its power UI. It is the sole owner of
  # the generic kernel platform profile; ASUS-specific controls stay in asusd.
  services.power-profiles-daemon.enable = true;

  services = {
    desktopManager.plasma6.enable = true;
    displayManager.sddm.enable = true;
    printing = {
      enable = true;
      drivers = [pkgs.cnijfilter2];
    };
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
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

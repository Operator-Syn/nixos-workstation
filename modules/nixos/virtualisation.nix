{
  virtualisation = {
    docker = {
      enable = true;
      daemon.settings.features.cdi = true;
    };

    libvirtd.enable = true;
  };
}

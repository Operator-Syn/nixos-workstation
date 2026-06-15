{pkgs, ...}: {
  virtualisation = {
    docker = {
      enable = true;
      package = pkgs.docker_29;
      daemon.settings.features.cdi = true;
    };

    libvirtd.enable = true;
  };
}

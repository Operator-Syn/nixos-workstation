{pkgs, ...}: {
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = false;
      package = pkgs.docker_29;
      daemon.settings.features.cdi = true;
    };
  };
}

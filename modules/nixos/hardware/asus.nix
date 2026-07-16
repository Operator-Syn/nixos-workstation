{
  config,
  lib,
  ...
}: let
  cfg = config.modules.asus;
in {
  options.modules.asus.enable = lib.mkEnableOption "ASUS laptop hardware support";

  # asusd and ROG Control Center own ASUS-specific firmware controls: fan
  # curves, charge limits, keyboard lighting, and Armoury features. KDE's
  # power-profiles-daemon owns the generic platform-profile endpoint.
  config = lib.mkIf cfg.enable {
    # This module is built by the newer kernels that support ASUS Armoury.
    # Load it early so asusd and ROG Control Center can use the advanced
    # profile, fan, and hardware controls after boot.
    boot.kernelModules = ["asus-armoury"];

    services.asusd = {
      enable = true;
      enableUserService = true;
    };

    # The packaged asusd unit has no [Install] section, so merely adding its
    # package leaves it linked but inactive. Start the packaged D-Bus service
    # with the normal multi-user boot target.
    systemd.services.asusd.wantedBy = ["multi-user.target"];

    programs.rog-control-center = {
      enable = true;
      autoStart = true;
    };

    # Keep GPU-mode changes in one native daemon. PRIME offload remains
    # configured by the host NVIDIA module; no AC/battery mode automation is
    # configured here.
    services.supergfxd.enable = true;
  };
}

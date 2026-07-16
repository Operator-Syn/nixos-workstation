{
  config,
  lib,
  ...
}: let
  cfg = config.modules.asus;
in {
  options.modules.asus.enable = lib.mkEnableOption "ASUS laptop hardware support";

  # ASUS/ROG Control Center provides the Armoury Crate-like controls exposed
  # by the laptop firmware on Linux (profiles, fans, charge limits, and RGB
  # where the model supports them).
  config = lib.mkIf cfg.enable {
    # This module is built by the newer kernels that support ASUS Armoury.
    # Load it early so asusd and ROG Control Center can use the advanced
    # profile, fan, and hardware controls after boot.
    boot.kernelModules = ["asus-armoury"];

    services.asusd = {
      enable = true;
      enableUserService = true;
    };

    programs.rog-control-center = {
      enable = true;
      autoStart = true;
    };

    # This NixOS unit is linked but not enabled by default in the current
    # asusctl package. Start it at boot so its DBus API is available to ROG
    # Control Center.
    systemd.services.asusd.wantedBy = ["multi-user.target"];

    # Provide the GPU mode/status DBus service used by ROG Control Center.
    services.supergfxd.enable = true;
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.msi;
  msiBootScript = pkgs.writeShellScript "msi-hardware-boot" ''
    if [ -d /sys/devices/platform/msi-ec ]; then
      echo turbo > /sys/devices/platform/msi-ec/shift_mode
      echo advanced > /sys/devices/platform/msi-ec/fan_mode
    else
      echo "MSI EC interface not found in /sys. Hardware might not be ready."
    fi
  '';
in {
  options.modules.msi.enable = lib.mkEnableOption "MSI hardware controls";

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [config.boot.kernelPackages.msi-ec];
    boot.kernelModules = [
      "msi-ec"
      "ec_sys"
    ];

    boot.kernelParams = [
      "ec_sys.write_support=1"
    ];

    systemd.services.msi-hardware-boot = {
      description = "Set MSI EC shift_mode to turbo and fan_mode to advanced";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${msiBootScript}";
      };
    };

    environment.etc."xdg/autostart/mcontrolcenter.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Exec=mcontrolcenter
      Hidden=false
      NoDisplay=false
      X-GNOME-Autostart-enabled=true
      Name=mControlCenter
      Comment=MSI Center for Linux
    '';

    environment.systemPackages = [
      pkgs.mcontrolcenter
    ];
  };
}

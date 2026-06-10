{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.easyeffects.enable =
    lib.mkEnableOption "EasyEffects";

  config = lib.mkIf config.modules.easyeffects.enable {
    home.packages = with pkgs; [
      easyeffects
    ];

    systemd.user.services.easyeffects = {
      Unit = {
        Description = "EasyEffects";
        Wants = [
          "pipewire.service"
          "pipewire-pulse.service"
        ];
        After = [
          "pipewire.service"
          "pipewire-pulse.service"
          "dbus.service"
        ];

        # Avoid systemd giving up permanently if EasyEffects fails
        # several times while audio is still waking up after suspend.
        StartLimitIntervalSec = 0;
      };

      Service = {
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'until ${pkgs.pipewire}/bin/pw-cli info >/dev/null 2>&1; do sleep 1; done'";
        ExecStart = "${lib.getExe pkgs.easyeffects} --gapplication-service";

        Restart = "always";
        RestartSec = 3;

        Type = "simple";
        TimeoutStartSec = 60;
        KillMode = "control-group";
      };

      Install = {
        WantedBy = [
          "default.target"
        ];
      };
    };
  };
}

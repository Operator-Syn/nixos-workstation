{ pkgs, ... }: {
  programs.plasma.kscreenlocker = {
    autoLock = false;
    timeout = 0;
  };

  programs.plasma.powerdevil = {
    AC = {
      autoSuspend.action = "nothing";
      powerProfile = "performance";
    };

    battery = {
      autoSuspend.action = "nothing";
      powerProfile = "balanced";
    };

    lowBattery = {
      autoSuspend.action = "nothing";
      powerProfile = "powerSaving";
    };

    batteryLevels.lowLevel = 30;
  };

  systemd.user.services.plasma-manual-inhibit = {
    Unit = {
      Description = "Keep Plasma sleep and screen locking manually blocked";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.kdePackages.kde-cli-tools}/bin/kde-inhibit --power --screenSaver ${pkgs.coreutils}/bin/sleep infinity";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}

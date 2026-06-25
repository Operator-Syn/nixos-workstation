{...}: {
  programs.plasma.powerdevil = {
    AC.autoSuspend.action = "nothing";
    battery.autoSuspend.action = "nothing";
    lowBattery.autoSuspend.action = "nothing";
  };
}

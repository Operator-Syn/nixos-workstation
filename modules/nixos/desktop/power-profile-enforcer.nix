{pkgs, ...}: let
  power-profile-enforcer = pkgs.writeShellScript "power-profile-enforcer" ''
    set -eu

    on_ac_power() {
      for device in /sys/class/power_supply/*; do
        [ -r "$device/type" ] || continue
        [ "$(cat "$device/type")" = "Mains" ] || continue
        [ -r "$device/online" ] || continue
        [ "$(cat "$device/online")" = "1" ] && return 0
      done

      return 1
    }

    battery_capacity() {
      for device in /sys/class/power_supply/*; do
        [ -r "$device/type" ] || continue
        [ "$(cat "$device/type")" = "Battery" ] || continue
        [ -r "$device/capacity" ] || continue
        cat "$device/capacity"
        return 0
      done

      return 1
    }

    if on_ac_power; then
      profile=performance
    else
      capacity="$(battery_capacity || true)"

      case "$capacity" in
        "" | *[!0-9]*)
          profile=balanced
          ;;
        *)
          if [ "$capacity" -lt 30 ]; then
            profile=power-saver
          else
            profile=balanced
          fi
          ;;
      esac
    fi

    current_profile="$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)"

    if [ "$current_profile" != "$profile" ]; then
      exec ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$profile"
    fi
  '';
in {
  systemd.services.power-profile-enforcer = {
    description = "Restore the configured Plasma power profile";
    after = ["power-profiles-daemon.service"];
    wants = ["power-profiles-daemon.service"];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = power-profile-enforcer;
    };
  };

  systemd.timers.power-profile-enforcer = {
    description = "Periodically restore the configured Plasma power profile";
    wantedBy = ["timers.target"];

    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "power-profile-enforcer.service";
    };
  };
}

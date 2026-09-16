{
  pkgs,
  lib,
  config,
  ...
}: let
  reminders = [
    {
      time = "09:00";
      label = "peak starts";
    }
    {
      time = "12:00";
      label = "peak ends";
    }
    {
      time = "14:00";
      label = "peak starts";
    }
    {
      time = "18:00";
      label = "peak ends";
    }
  ];

  peakHours = pkgs.writeShellScriptBin "peak-hours" ''
    set -euo pipefail

    date_cmd="${pkgs.coreutils}/bin/date"
    notify_send="${pkgs.libnotify}/bin/notify-send"
    badge_dir="${config.home.homeDirectory}/.local/share/icons/hicolor/scalable/apps"

    mode="''${1:-status}"

    # Sets now_stamp to "<weekday> <hour> <minute>" from the wall clock, or from
    # PEAK_HOURS_NOW when that test override is set.
    now_stamp=""
    now_stamp() {
      if [ -n "''${PEAK_HOURS_NOW:-}" ]; then
        now_stamp="$("$date_cmd" -d "''${PEAK_HOURS_NOW}" '+%u %H %M' 2>/dev/null || true)"
        if [ -z "$now_stamp" ]; then
          printf 'peak-hours: invalid PEAK_HOURS_NOW value: %s\n' "''${PEAK_HOURS_NOW}" >&2
          exit 2
        fi
      else
        now_stamp="$("$date_cmd" '+%u %H %M')"
      fi
    }

    # Peak windows as "start end" week minutes since Monday 00:00. Weekdays
    # only: 09:00-12:00 and 14:00-18:00, local time (Asia/Manila).
    week_windows() {
      local day
      for day in 0 1 2 3 4; do
        printf '%s %s\n' "$((day * 1440 + 540))" "$((day * 1440 + 720))"
        printf '%s %s\n' "$((day * 1440 + 840))" "$((day * 1440 + 1080))"
      done
    }

    day_name() {
      case "$1:$2" in
        0:long) printf 'Monday' ;;
        1:long) printf 'Tuesday' ;;
        2:long) printf 'Wednesday' ;;
        3:long) printf 'Thursday' ;;
        4:long) printf 'Friday' ;;
        5:long) printf 'Saturday' ;;
        6:long) printf 'Sunday' ;;
        0:short) printf 'Mon' ;;
        1:short) printf 'Tue' ;;
        2:short) printf 'Wed' ;;
        3:short) printf 'Thu' ;;
        4:short) printf 'Fri' ;;
        5:short) printf 'Sat' ;;
        *) printf 'Sun' ;;
      esac
    }

    format_time() {
      printf '%02d:%02d' "$((($1 % 1440) / 60))" "$(($1 % 60))"
    }

    # A target in the current day prints as "12:00", a later day as
    # "Mon 09:00" or "Monday 09:00".
    format_target() {
      local target="$1"
      local style="''${2:-short}"
      local target_day="$((($1 / 1440) % 7))"
      if [ "$target_day" = "$now_day" ]; then
        format_time "$target"
      else
        printf '%s %s' "$(day_name "$target_day" "$style")" "$(format_time "$target")"
      fi
    }

    format_duration() {
      local total="$1"
      if [ "$((total / 60))" -gt 0 ]; then
        printf '%dh %02dm' "$((total / 60))" "$((total % 60))"
      else
        printf '%dm' "$((total % 60))"
      fi
    }

    now_stamp
    read -r weekday hour minute <<<"$now_stamp"
    now=$(((10#$weekday - 1) * 1440 + 10#$hour * 60 + 10#$minute))
    now_day=$((now / 1440))
    in_peak=false
    peak_end=0
    last_transition=-1
    week_last_transition=0
    # Monday 09:00 of the next week is the default for late Friday, Saturday,
    # and Sunday.
    next_start=$((7 * 1440 + 540))

    while read -r start end; do
      if [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]; then
        in_peak=true
        peak_end="$end"
      fi
      if [ "$start" -gt "$now" ] && [ "$start" -lt "$next_start" ]; then
        next_start="$start"
      fi
      for transition in "$start" "$end"; do
        if [ "$transition" -le "$now" ] && [ "$transition" -gt "$last_transition" ]; then
          last_transition="$transition"
        fi
        if [ "$transition" -gt "$week_last_transition" ]; then
          week_last_transition="$transition"
        fi
      done
    done < <(week_windows)

    # The current stretch started at the last transition; before Monday 09:00
    # that is Friday 18:00 of the previous week.
    if [ "$last_transition" -lt 0 ]; then
      last_transition=$((week_last_transition - 10080))
    fi
    segment_start="$last_transition"
    if [ "$in_peak" = true ]; then
      segment_end="$peak_end"
    else
      segment_end="$next_start"
    fi

    status_line() {
      if [ "$in_peak" = true ]; then
        printf 'PEAK · ends %s (%s)\n' "$(format_target "$peak_end")" "$(format_duration "$((peak_end - now))")"
      else
        printf 'OFF-PEAK · peak %s (%s)\n' "$(format_target "$next_start")" "$(format_duration "$((next_start - now))")"
      fi
    }

    # Rich text for the desktop widget: the command output plasmoid renders
    # inline markup, so each state gets its own accent color and progress bar.
    progress_bar() {
      local width="$1"
      local accent="$2"
      local span=$((segment_end - segment_start))
      local filled=0
      local empty=0
      local filled_bar=""
      local empty_bar=""
      local index=0
      if [ "$span" -le 0 ]; then
        span=1
      fi
      filled=$(( (now - segment_start) * width / span ))
      if [ "$filled" -lt 0 ]; then
        filled=0
      fi
      if [ "$filled" -gt "$width" ]; then
        filled="$width"
      fi
      empty=$((width - filled))
      while [ "$index" -lt "$filled" ]; do
        filled_bar+='█'
        index=$((index + 1))
      done
      index=0
      while [ "$index" -lt "$empty" ]; do
        empty_bar+='░'
        index=$((index + 1))
      done
      if [ -n "$filled_bar" ]; then
        printf '<font color="%s">%s</font>' "$accent" "$filled_bar"
      fi
      printf '<font color="#453a7d">%s</font>' "$empty_bar"
    }

    widget_text() {
      # Colors are lifted from the Scarlet Tree night wallpaper: comet cyan for
      # off-peak, canopy scarlet for peak, cloud lavender for the detail line.
      local accent="#8ee6e6"
      local label="● OFF-PEAK"
      local detail
      if [ "$in_peak" = true ]; then
        accent="#f2606f"
        label="▲ PEAK HOURS"
        detail="$(format_duration "$((peak_end - now))") left · until $(format_time "$peak_end")"
      else
        detail="next peak in $(format_duration "$((next_start - now))") · $(format_target "$next_start")"
      fi
      printf '<b><font color="%s">%s</font></b><br><font color="#c9c6ee">%s</font><br>%s\n' \
        "$accent" "$label" "$detail" "$(progress_bar 14 "$accent")"
    }

    # The message is derived from the current time, so a reminder that fires
    # late (for example after resuming) still describes the present window.
    # Plasma renders the body as rich text (the notification server advertises
    # body-markup), so each reminder repeats the widget's palette: a colored
    # state line above a lavender detail line, with a matching badge icon.
    notify_now() {
      local accent="#8ee6e6"
      local badge="$badge_dir/peak-hours-offpeak.svg"
      local state="● Off-peak pricing"
      local detail="Peak starts $(format_target "$next_start") · in $(format_duration "$((next_start - now))")"
      if [ "$in_peak" = true ]; then
        accent="#f2606f"
        badge="$badge_dir/peak-hours-peak.svg"
        state="▲ Peak pricing"
        detail="Off-peak resumes $(format_time "$peak_end") · in $(format_duration "$((peak_end - now))")"
      fi

      "$notify_send" -a 'Peak hours' -u normal -t 3000 -i "$badge" 'Peak hours' \
        "<b><font color=\"$accent\">$state</font></b><br><font color=\"#c9c6ee\">$detail</font>"
    }

    schedule_text() {
      printf '%s\n' \
        'Peak hours (Asia/Manila, weekdays)' \
        'Mon-Fri 09:00-12:00 and 14:00-18:00' \
        'All other hours, including weekends, are off-peak.' \
        'Off-peak pricing is 50% of peak pricing.'
    }

    case "$mode" in
      status)
        status_line
        ;;
      widget)
        widget_text
        ;;
      notify)
        notify_now
        ;;
      schedule)
        schedule_text
        ;;
      *)
        printf 'Usage: peak-hours [status|widget|notify|schedule]\n' >&2
        exit 2
        ;;
    esac
  '';
in {
  options.modules.peak-hours.enable = lib.mkEnableOption "Peak-hour reminders and desktop widget";

  config = lib.mkIf config.modules.peak-hours.enable {
    home.packages = [
      pkgs.plasma-applet-commandoutput
      peakHours
    ];

    xdg.dataFile."plasma/plasmoids/com.github.zren.commandoutput".source = "${pkgs.plasma-applet-commandoutput}/share/plasma/plasmoids/com.github.zren.commandoutput";

    # Stable paths for the notification badges: reminders keep pointing at the
    # installed icons instead of store paths that a later rebuild may drop.
    home.file = {
      ".local/share/icons/hicolor/scalable/apps/peak-hours-offpeak.svg".source = ../plasma/icons/peak-hours-offpeak.svg;
      ".local/share/icons/hicolor/scalable/apps/peak-hours-peak.svg".source = ../plasma/icons/peak-hours-peak.svg;
    };

    # The command output widget renders the current peak state on the desktop.
    # Its position and size stay owned by Plasma: `programs.plasma.desktop.widgets`
    # would remove every desktop widget and re-create this one at a fixed spot
    # whenever the generated layout script changes, which discards user moves.
    # This script only ensures the widget exists and refreshes its configuration.
    programs.plasma.startup.desktopScript.peak_hours_widget = {
      priority = 2;
      text = ''
        const peakHoursWidget = "com.github.zren.commandoutput";
        for (const desktop of desktops()) {
          let widget = desktop.widgets(peakHoursWidget)[0];
          if (!widget) {
            // First creation only, at the top left; later moves are stored by
            // Plasma itself.
            widget = desktop.addWidget(peakHoursWidget, 16, 16, 480, 144);
          }
          widget.currentConfigGroup = ["General"];
          widget.writeConfig("command", "${peakHours}/bin/peak-hours widget");
          widget.writeConfig("clickCommand", "${peakHours}/bin/peak-hours notify");
          widget.writeConfig("tooltipCommand", "${peakHours}/bin/peak-hours schedule");
          widget.writeConfig("interval", 30000);
          widget.writeConfig("showBackground", true);
          widget.writeConfig("fontSize", 13);
          widget.writeConfig("textAlign", 4);
          widget.writeConfig("vertAlign", 128);
        }
      '';
    };

    systemd.user.services.peak-hours-notify = {
      Unit = {
        Description = "Send the current peak or off-peak reminder";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${peakHours}/bin/peak-hours notify";
      };
    };

    # Each weekday boundary starts the same notify service. Because the
    # message is derived from the current time, a missed reminder that fires
    # after resume never reports a window that has already passed.
    systemd.user.timers = lib.listToAttrs (map (reminder: {
        name = "peak-hours-${lib.replaceStrings [":"] [""] reminder.time}";
        value = {
          Unit = {
            Description = "Peak-hours reminder (${reminder.label}) at ${reminder.time}";
          };

          Timer = {
            OnCalendar = "Mon-Fri ${reminder.time}";
            Persistent = true;
            AccuracySec = "1s";
            Unit = "peak-hours-notify.service";
          };

          Install.WantedBy = ["timers.target"];
        };
      })
      reminders);
  };
}

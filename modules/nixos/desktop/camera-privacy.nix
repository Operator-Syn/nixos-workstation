{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.camera-privacy;

  # Runtime intent of the switch. /run is cleared on every boot, so an absent
  # file falls back to the configured boot state.
  stateFile = "/run/camera-privacy.state";

  defaultState =
    if cfg.blockAtBoot
    then "blocked"
    else "allowed";

  cameraPrivacy = pkgs.writeShellScriptBin "camera-privacy" ''
    set -euo pipefail

    mode="''${1:-toggle}"
    case "$mode" in
      toggle | block | allow | apply | udev | status) ;;
      *)
        echo "Usage: camera-privacy [toggle|block|allow|status]" >&2
        exit 2
        ;;
    esac

    vendor="${cfg.usbVendor}"
    product="${cfg.usbProduct}"
    state_file="${stateFile}"
    default_state="${defaultState}"
    sysfs_usb="/sys/bus/usb/devices"

    cat="${pkgs.coreutils}/bin/cat"
    id="${pkgs.coreutils}/bin/id"
    printf="${pkgs.coreutils}/bin/printf"
    notify="${pkgs.libnotify}/bin/notify-send"
    systemctl="${pkgs.systemd}/bin/systemctl"
    udevadm="${pkgs.systemd}/bin/udevadm"

    # Print the sysfs path of every USB device with the configured IDs. The
    # identity attributes stay readable while a device is deauthorized, so the
    # switch can find the camera again without the driver being bound.
    camera_devices() {
      local dev
      for dev in "$sysfs_usb"/*; do
        [ -r "$dev/idVendor" ] || continue
        [ "$("$cat" "$dev/idVendor")" = "$vendor" ] || continue
        [ "$("$cat" "$dev/idProduct")" = "$product" ] || continue
        "$printf" '%s\n' "$dev"
      done
    }

    camera_state() {
      local dev auth found=0 blocked=0
      while IFS= read -r dev; do
        found=1
        auth="$("$cat" "$dev/authorized" 2>/dev/null || true)"
        if [ "$auth" != "1" ]; then
          blocked=1
        fi
      done < <(camera_devices)

      if [ "$found" -eq 0 ]; then
        "$printf" 'absent'
      elif [ "$blocked" -eq 1 ]; then
        "$printf" 'blocked'
      else
        "$printf" 'enabled'
      fi
    }

    print_state() {
      case "$(camera_state)" in
        blocked)
          echo "Webcam is blocked."
          ;;
        enabled)
          echo "Webcam is enabled."
          ;;
        absent)
          echo "Webcam is not detected."
          ;;
      esac
    }

    apply_state() {
      local target="$1"
      local dev auth want=1 changed=0
      if [ "$target" = "blocked" ]; then
        want=0
      fi

      while IFS= read -r dev; do
        auth="$("$cat" "$dev/authorized" 2>/dev/null || true)"
        if [ "$auth" != "$want" ]; then
          "$printf" '%s' "$want" > "$dev/authorized"
          changed=1
        fi
      done < <(camera_devices)

      # udev calls this script from its own event worker, where waiting for the
      # event queue would stall until the timeout.
      if [ "$changed" -eq 1 ] && [ "$mode" != "udev" ]; then
        "$udevadm" settle --timeout=10 || true
      fi
    }

    if [ "$("$id" -u)" -eq 0 ]; then
      if [ "$mode" = "status" ]; then
        print_state
        exit 0
      fi

      case "$mode" in
        toggle)
          if [ "$(camera_state)" = "enabled" ]; then
            target="blocked"
          else
            target="allowed"
          fi
          ;;
        block)
          target="blocked"
          ;;
        allow)
          target="allowed"
          ;;
        *)
          if [ -r "$state_file" ]; then
            target="$("$cat" "$state_file")"
          else
            target="$default_state"
          fi
          ;;
      esac

      # A missing or edited state file must not disable the switch.
      case "$target" in
        blocked | allowed) ;;
        *)
          target="$default_state"
          ;;
      esac

      case "$mode" in
        toggle | block | allow)
          "$printf" '%s\n' "$target" > "$state_file"
          ;;
      esac

      apply_state "$target"
      exit 0
    fi

    case "$mode" in
      status)
        print_state
        exit 0
        ;;
      apply | udev)
        echo "Usage: camera-privacy [toggle|block|allow|status]" >&2
        exit 2
        ;;
    esac

    if ! "$systemctl" start -- "camera-privacy@$mode.service"; then
      "$notify" -u critical -a "Camera privacy" "Camera privacy" "Could not change the webcam state." || true
      exit 1
    fi

    case "$(camera_state)" in
      blocked)
        "$notify" -a "Camera privacy" "Camera privacy" "Webcam blocked." || true
        ;;
      enabled)
        "$notify" -a "Camera privacy" "Camera privacy" "Webcam enabled." || true
        ;;
      absent)
        "$notify" -a "Camera privacy" "Camera privacy" "Webcam not detected." || true
        ;;
    esac
  '';
in {
  options.modules.camera-privacy = {
    enable = lib.mkEnableOption "the webcam privacy switch";

    usbVendor = lib.mkOption {
      type = lib.types.str;
      example = "2b7e";
      description = "USB vendor ID of the camera the switch controls.";
    };

    usbProduct = lib.mkOption {
      type = lib.types.str;
      example = "b888";
      description = "USB product ID of the camera the switch controls.";
    };

    blockAtBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the camera starts blocked after a boot. The runtime state is
        kept in ${stateFile} until the next boot.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cameraPrivacy];

    # The camera is a USB device, so the switch deauthorizes the device instead
    # of unloading uvcvideo: WirePlumber keeps the media device open, which
    # keeps the module busy. Deauthorizing the device also survives resume,
    # because this rule re-applies the stored state on every enumeration.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="${cfg.usbVendor}", ATTR{idProduct}=="${cfg.usbProduct}", RUN+="${cameraPrivacy}/bin/camera-privacy udev"
    '';

    systemd.services."camera-privacy@" = {
      description = "Webcam privacy switch (%i)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cameraPrivacy}/bin/camera-privacy %i";
      };
    };

    # Covers boot and the first activation of this module, where the camera is
    # already enumerated and no device add event is going to happen.
    systemd.services.camera-privacy-apply = {
      description = "Apply the configured webcam privacy state";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cameraPrivacy}/bin/camera-privacy apply";
      };
    };

    # The switch is a desktop control, so wheel members may turn it without a
    # password prompt. Only the switch units are reachable this way; no tool
    # gains general root access.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id != "org.freedesktop.systemd1.manage-units") {
          return;
        }
        if (!subject.isInGroup("wheel")) {
          return;
        }
        var unit = action.lookup("unit");
        if (unit != "camera-privacy@block.service" &&
            unit != "camera-privacy@allow.service" &&
            unit != "camera-privacy@toggle.service") {
          return;
        }
        if (action.lookup("verb") == "start") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}

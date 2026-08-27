{pkgs, ...}: {
  programs.dconf.enable = true;
  programs.firefox = {
    enable = true;
    package = pkgs.firefox-esr;
  };

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
  ];

  security.rtkit.enable = true;

  # Plasma exposes this D-Bus service in its power UI. It is the sole owner of
  # the generic kernel platform profile; ASUS-specific controls stay in asusd.
  services.power-profiles-daemon.enable = true;

  services = {
    desktopManager.plasma6.enable = true;
    displayManager.sddm.enable = true;
    printing = {
      enable = true;
      drivers = [pkgs.cnijfilter2];
    };
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
    pulseaudio.enable = false;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;

      wireplumber.extraConfig."51-hiraeth-audio-routing" = {
        "wireplumber.settings" = {
          # Keep Bluetooth playback devices in A2DP mode when Discord uses the
          # separate external microphone.
          "bluetooth.autoswitch-to-headset-profile" = false;
          "device.restore-profile" = false;
        };

        # Hiraeth has a separate external microphone. Avoid HFP/HSP and AAC
        # renegotiation, which can make Bluetooth playback transports flap
        # when audio is paused and resumed.
        "monitor.bluez.properties" = {
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
          ];
          "bluez5.codecs" = [
            "sbc"
          ];
        };

        "device.profile.priority.rules" = [
          {
            matches = [
              {"device.name" = "~bluez_card.*";}
            ];
            actions = {
              "update-props" = {
                priorities = [
                  "a2dp-sink-sbc"
                  "a2dp-sink-sbc_xq"
                  "a2dp-sink"
                ];
              };
            };
          }
        ];

        "monitor.bluez.rules" = [
          {
            matches = [
              {"node.name" = "~bluez_output.*";}
            ];
            actions = {
              "update-props" = {
                "priority.session" = 2000;
                "session.suspend-timeout-seconds" = 0;
              };
            };
          }
        ];

        "monitor.alsa.rules" = [
          {
            matches = [
              {"node.name" = "alsa_input.usb-Shenzhen_Hollyland_Technology_Co._Ltd_Wireless_microphone_C6FX222T472-01.pro-input-0";}
            ];
            actions = {
              "update-props" = {
                "priority.session" = 2000;
              };
            };
          }
        ];
      };
    };

    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };
}

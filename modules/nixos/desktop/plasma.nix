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
          # Keep Bluetooth earbuds in playback mode when Discord uses the
          # separate external microphone.
          "bluetooth.autoswitch-to-headset-profile" = false;
          "device.restore-profile" = false;
        };

        "device.profile.priority.rules" = [
          {
            matches = [
              {"device.name" = "bluez_card.41_42_FF_40_94_73";}
            ];
            actions = {
              "update-props" = {
                priorities = [
                  "a2dp-sink"
                  "a2dp-sink-sbc_xq"
                  "a2dp-sink-sbc"
                ];
              };
            };
          }
        ];

        "monitor.bluez.rules" = [
          {
            matches = [
              {"node.name" = "bluez_output.41_42_FF_40_94_73.1";}
            ];
            actions = {
              "update-props" = {
                "priority.session" = 2000;
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

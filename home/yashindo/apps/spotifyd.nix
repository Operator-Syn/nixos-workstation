{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.modules.spotifyd;
in {
  options.modules.spotifyd.enable = lib.mkEnableOption "Spotifyd";

  config = lib.mkIf cfg.enable {
    services.spotifyd = {
      enable = true;
      package = pkgs.spotifyd;

      settings.global = {
        # Spotify Connect display
        device_name = "hiraeth";
        device_type = "computer"; # unknown, computer, tablet, smartphone, speaker, t_v, a_v_r, s_t_b, audio_dongle

        # Audio
        # For PipeWire, try pulseaudio first because PipeWire usually provides PulseAudio compatibility.
        # If this gives trouble as a system service, ALSA may be more predictable.
        backend = "pulseaudio";
        # backend = "alsa";
        # device = "default";

        # Quality
        bitrate = 320; # valid values documented by spotifyd: 96, 160, 320

        # Startup behavior
        initial_volume = 100;
        volume_normalisation = true;
        normalisation_pregain = -5.0;
        autoplay = true;

        # Cache behavior
        # NixOS already starts spotifyd with --cache-path /var/cache/spotifyd,
        # so do not set cache_path here unless you also override ExecStart.
        #
        # However, this module appears to be used through Home Manager / user-level services,
        # so we explicitly set a stable user cache path.
        #
        # Do not use "~/.cache/spotifyd" here because spotifyd does not shell-expand "~".
        cache_path = "/home/yashindo/.cache/spotifyd";
        no_audio_cache = false;
        max_cache_size = 1000000000; # about 1GB

        # Discovery / Spotify Connect visibility
        # Keep false if you want it visible on the LAN.
        disable_discovery = false;

        # Optional: pin the zeroconf TCP port if you use a firewall.
        # You also need mDNS UDP 5353 for discovery.
        # zeroconf_port = 1234;

        # MPRIS / playerctl integration
        # For the stock NixOS system service, false is often safer.
        # Session DBus is usually not available to a system DynamicUser service.
        use_mpris = false;
        # dbus_type = "system";

        # Optional hook on song change.
        # on_song_change_hook = "${pkgs.libnotify}/bin/notify-send 'Spotifyd' \"$PLAYER_EVENT\"";

        # Optional proxy.
        # proxy = "http://proxy.example.org:8080";
      };
    };

    # If using a fixed zeroconf_port and you want discovery from other devices:
    # networking.firewall.allowedUDPPorts = [5353];
    # networking.firewall.allowedTCPPorts = [1234];
  };
}

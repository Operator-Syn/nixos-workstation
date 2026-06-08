{
  pkgs,
  lib,
  config,
  ...
}: {
  options.modules.spotify-player.enable = lib.mkEnableOption "Spotify Player";

  config = lib.mkIf config.modules.spotify-player.enable {
    home.packages = [pkgs.spotify-player];

    # Directly managing the config file to enable the visualizer
    xdg.configFile."spotify-player/app.toml".text = ''
      enable_audio_visualization = true
      visualization_type = "Spectrum"
      visualization_framerates = 60
    '';

    systemd.user.services.spotify-player = {
      Unit = {
        Description = "Spotify Player Daemon";
        After = ["network.target" "sound.target"];
      };
      Install = {
        WantedBy = ["default.target"];
      };
      Service = {
        ExecStart = "${pkgs.spotify-player}/bin/spotify_player --daemon";
        Restart = "always";
      };
    };
  };
}

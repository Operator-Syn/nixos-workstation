{
  pkgsUnstable,
  lib,
  config,
  ...
}: {
  options.modules.ncspot.enable = lib.mkEnableOption "ncspot";

  config = lib.mkIf config.modules.ncspot.enable {
    # ncspot embeds the librespot playback stack and uses the PulseAudio
    # backend by default, which routes through PipeWire-Pulse on Hiraeth.
    # It is intentionally interactive rather than a user service or autostart
    # daemon.
    home.packages = [pkgsUnstable.ncspot];
  };
}

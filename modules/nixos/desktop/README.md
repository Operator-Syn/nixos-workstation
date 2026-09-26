# Desktop audio

[plasma.nix](plasma.nix) enables PipeWire and configures WirePlumber for the
Hiraeth desktop. Its Spotify stream rule disables saved stream-volume restoration
for the Spotify desktop app only. A new Spotify stream starts at its normal
application volume and follows the selected output device's volume. Other apps
keep WirePlumber's usual per-stream volume behavior.

The NixOS declaration takes effect after system activation. Source validation
alone does not change the running WirePlumber service.

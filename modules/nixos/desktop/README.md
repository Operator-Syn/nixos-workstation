# Desktop audio and power

## Power profiles

Plasma PowerDevil selects the generic power profile: Performance on AC, Balanced
on battery, and Power Saver when battery reaches the configured low level of
15%. The power-profiles-daemon exposes those choices to Plasma, while asusd
applies ASUS-specific platform and CPU policies. No separate timer overrides
Plasma's selection.

The profile declarations live in
[prevent-sleep.nix](../../../home/yashindo/plasma/prevent-sleep.nix). The
NixOS configuration enables power-profiles-daemon in
[plasma.nix](plasma.nix). These declarative settings take effect after system
activation; source validation alone does not change the running profile.

## Audio

[plasma.nix](plasma.nix) enables PipeWire and configures WirePlumber for the
Hiraeth desktop. Its Spotify stream rule disables saved stream-volume restoration
for the Spotify desktop app only. A new Spotify stream starts at its normal
application volume and follows the selected output device's volume. Other apps
keep WirePlumber's usual per-stream volume behavior.

The NixOS declaration takes effect after system activation. Source validation
alone does not change the running WirePlumber service.

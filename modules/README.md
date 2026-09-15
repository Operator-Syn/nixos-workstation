# NixOS Modules

Reusable system-level modules live here.

These files describe behavior that can be imported by hosts. The `Hiraeth` host currently imports modules from `modules/nixos/` through `hosts/hiraeth/default.nix`.

---

## Layout

```text
modules/
`-- nixos/
    |-- core/             locale, Nix settings, security, zram
    |-- desktop/          Plasma, audio, camera privacy, display manager
    |-- development/      Distrobox and system-level development support
    |-- hardware/         Bluetooth and reusable hardware-related modules
    |-- users/             system user declarations
    |-- bedrock-on-linux/  BedrockOnLinux launcher package and NixOS module
    |-- netbird.nix       NetBird VPN client
    |-- ollama.nix        optional local Ollama service
    |-- kvm-manager.nix   KVM/libvirt and virt-manager
    |-- networking.nix    NetworkManager
    |-- openssh.nix       hardened OpenSSH server
    |-- packages.nix      system package list
    |-- scripts.nix       helper commands
    |-- steam.nix         Steam, GameMode, launchers, and Proton tools
    |-- steam/            Steam submodules
    `-- virtualisation.nix Docker
```

## Module Index

| Area | Owns |
| --- | --- |
| `core/` | Nix settings, locale, sudo, polkit, zram, user-slice OOM protection |
| `desktop/` | Plasma 6, SDDM, PipeWire, printing, XKB, webcam privacy switch |
| `development/` | Distrobox setup, declared mutable boxes, optional Python support, containers |
| `hardware/` | Bluetooth and reusable ASUS hardware support |
| `users/` | system users, shells, groups |
| `bedrock-on-linux/` | BedrockOnLinux launcher package and NixOS module |
 | `netbird.nix` | NetBird VPN client |
| `ollama.nix` | optional local Ollama service; currently not enabled by Hiraeth |
| `openssh.nix` | OpenSSH server with password and root login disabled |
| `packages.nix` | system-wide packages |
| `scripts.nix` | `rebuild`, `hermes-restart`, `update-system`, `update-codex`, `update-hardware`, `wifi-hotspot`, `nvrun`, `getGPU` |
| `steam.nix` and `steam/` | Steam, GameMode (including `gamemode-toggle`), gamescope, launchers, and Protontricks support |
| `kvm-manager.nix` | KVM/libvirt services, default network startup, and virt-manager |
| `virtualisation.nix` | Docker service |

The desktop module removes a stale `/run/avahi-daemon/pid` marker immediately
before Avahi starts. This handles a dead runtime PID left by a prior service
reactivation without changing Avahi discovery configuration or persistent
state.

## Good Module Shape

Optional modules should expose an enable option:

```nix
{
  config,
  lib,
  ...
}: let
  cfg = config.modules.example;
in {
  options.modules.example.enable = lib.mkEnableOption "Example module";

  config = lib.mkIf cfg.enable {
    # system config here
  };
}
```

Always keep the option name close to the feature it controls.

## Boundary Rules

| If It Is... | Put It In... |
| --- | --- |
| Reusable system behavior | `modules/nixos/` |
| Host-specific hardware or identity | `hosts/<name>/` |
| User-session behavior | `home/` |
| Project-specific tooling | `devshells/` |
| Mutable dependency experiments | `modules/nixos/development/distrobox-*.nix` |

## Development Modules

| File | Owns |
| --- | --- |
| `development/distrobox.nix` | Distrobox package and Docker backend selection |
| `development/distrobox-debian-dev.nix` | `debian-dev` assemble manifest and helper command |
| `development/debian-container.nix` | Previous Docker-managed Debian container module, currently not imported by `hiraeth` |
| `development/python-shell.nix` | Optional system-level Python support, enabled on `hiraeth`; keeps `playwright-driver.browsers` as a package and leaves browser path selection to each project |

The Python module retains `playwright-driver.browsers` for Nix-managed workflows but intentionally does not export `PLAYWRIGHT_BROWSERS_PATH`. `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` keeps browser installation explicit/manual; project-local setup must choose a browser location matching its Playwright version. Native Playwright runtime variables remain scoped to the dev shells.

The global package and `nix-ld` surfaces also provide the Linux runtime needed
by Hermes' optional Browser Use and Computer Use integrations: `uv`,
`at-spi2-core`, `xorg.libXi`, and `xorg.libXtst`. Hermes Desktop installs the
Browser Use CLI and `cua-driver` into user-owned state when their tool settings
are enabled; Nix activation does not download those binaries or credentials.
Hiraeth remains on the default XWayland path, and no static Chrome/Brave CDP
endpoint is declared.

The Distrobox base module and individual box declarations are kept separate so installing Distrobox is not coupled to creating a specific mutable development box.

## Editing Notes

- Keep modules focused on one concern.
- Prefer imports over giant files.
- Avoid putting personal desktop settings in system modules.
- Avoid putting host-only values such as GPU bus IDs in reusable modules.

`wifi-hotspot` discovers a Wi-Fi adapter with AP support, prompts for the
SSID and password, and lets NetworkManager choose a compatible band and channel.
It uses an active Ethernet connection for internet sharing and accepts optional
interface, SSID, and connection-name arguments: `wifi-hotspot [interface] [ssid]
[connection-name]`. Existing profiles with the chosen name are repaired to AP
mode when possible.

`desktop/camera-privacy.nix` owns the webcam privacy switch for the USB camera
declared by `modules.camera-privacy.usbVendor` and
`modules.camera-privacy.usbProduct`. A blocked camera is a deauthorized USB
device, so no application can open it even though `uvcvideo` stays loaded. Run
`camera-privacy` or `camera-privacy toggle` to switch the state, `camera-privacy
block` and `camera-privacy allow` to set it explicitly, and `camera-privacy
status` to report it; the Plasma shortcut `Meta+Shift+C` runs the toggle. The
state lives in `/run/camera-privacy.state` and resets to
`modules.camera-privacy.blockAtBoot` after each boot, a udev rule re-applies it
whenever the camera is enumerated again, and a polkit rule scoped to `wheel`
keeps the toggle passwordless. The OBS virtual camera from `obs-studio.nix` is
not affected, and none of this is live until the host is activated with `rb`.

`gamemode-toggle` controls a manual GameMode request without changing a game's
launch options. Run `gamemode-toggle` or `gamemode-toggle toggle` to switch it,
or use `on`, `off`, and `status` explicitly. This manual request is separate
from per-game requests; stopping the manual request does not override a game
that is still requesting GameMode.

While GameMode has at least one active client, its custom hooks temporarily set
KDE's global `AnimationDurationFactor` to `0` and restore the previous value when
the last client exits. This keeps the Plasma session's animation policy unchanged
outside games, and also applies to the manual `gamemode-toggle` request.

The same GameMode hooks stop containers that were already running when GameMode
started, then start those exact containers again when the last client exits. If
Docker is unavailable or no containers are running, the hook leaves it unchanged.

The `memory-animation-guard.service` runs with each Plasma graphical
session. It treats `MemAvailable <= 15%` for 30 seconds as sustained
pressure and suppresses only Plasma animations; it does not activate GameMode,
change CPU or I/O policy, inhibit the screensaver, or touch Docker. Animations
return after `MemAvailable >= 25%` for 60 seconds. The guard shares
animation ownership with GameMode so either active reason keeps animations
suppressed.

For Steam, the standard per-game launch option is `gamemoderun %command%`. On
Hiraeth, use `nvrun %command%` when the game should also use NVIDIA PRIME
offload; it combines GameMode with the same PRIME variables as NixOS’s generated
`nvidia-offload` helper. `gamemoded -s` reports whether GameMode is active, and
`gamemoded -t` runs the installation diagnostics.

The Steam module also exposes a Steam Gamescope Wayland session through the
display manager. It uses the pinned NixOS Gamescope defaults and `cap_sys_nice`;
select it from SDDM when a Gamescope session is desired, while the normal Plasma
session remains unchanged.

## Hiraeth ASUS Controls

`hardware/asus.nix` owns the native Linux ASUS stack: `asusd`,
`asusctl`, ROG Control Center, and `supergfxd`. Keep host-specific kernel and
NVIDIA PRIME settings in `hosts/hiraeth/`.

KDE Plasma's `power-profiles-daemon` owns the generic platform profile. ASUS
controls remain responsible for firmware-specific features such as charge
thresholds, keyboard lighting, fan curves, and Armoury features. Do not add
Windows G-Helper, Wine, or a second GPU-switching daemon to this stack.

# Home Manager

User-level configuration for the `yashindo` profile.

This layer owns the interactive desktop session: apps, shell behavior, editor settings, browser preferences, user packages, and Plasma customization.

---

## Layout

```text
home/
`-- yashindo/
    |-- default.nix      user entry point
    |-- packages.nix     user-level package list
    |-- apps/            application modules and toggles
    `-- plasma/          Plasma Manager config and assets
```

## Entry Points

| File | Role |
| --- | --- |
| `home/yashindo/default.nix` | Imports user packages, app modules, Plasma modules |
| `home/yashindo/packages.nix` | Packages installed for the user profile |
| `home/yashindo/apps/default.nix` | App imports and enable toggles |
| `home/yashindo/plasma/default.nix` | Plasma imports and enable toggles |

## Belongs Here

| Category | Examples |
| --- | --- |
| Terminal and shell | Alacritty, fish, starship |
| Apps | Brave, Google Chrome, Firefox, Discord, Obsidian, VS Code, Hermes Desktop, OpenCode CLI |
| User packages | fonts, utilities, creative tools |
| Desktop preferences | Plasma panels, colors, wallpaper, icons |
| User services | app-level user services and autostart entries |

KWin's Blur effect is explicitly disabled in
`home/yashindo/plasma/desktop-settings.nix` while compositor offscreen-framebuffer
errors are being investigated; the other configured effects remain unchanged.

VS Code user settings, language-specific formatters, Nix language-server
configuration, terminal defaults, and trusted schema domains are declared in
`home/yashindo/apps/vscode.nix`. By default, the declared settings seed a
writable `~/.config/Code/User/settings.json`; imperative edits are retained
and take precedence over declarative defaults. Set
`modules.vscode.mutableUserSettings = false` for a fully Home Manager-managed
(read-only) settings file. Rust Analyzer is pointed at the Nix-provided wrapper,
which supplies standard-library sources matching the system Rust toolchain.

General-purpose language runtimes such as Node and Python should usually stay out of `home/yashindo/packages.nix`. Prefer `devshells/` for project-scoped tooling and Distrobox for mutable dependency experiments.

Brave and Discord launch directly on the AMD integrated GPU with no
GPU-selection dialog. `home/yashindo/apps/brave.nix` keeps the package's own
desktop entry and `BROWSER=brave`, with no second-profile Brave Work launcher;
`home/yashindo/apps/discord.nix` keeps the package's own desktop entry and
autostarts Discord minimized at login without a prompt. `nvidia-offload`
remains available from a terminal for dedicated-GPU launches, and the Discord
Professional module stays available but disabled in the active profile.

The Obsidian module exposes `obsidian` (CLI), `obsidian-cli` (compatibility
name), and `obsidian-desktop` (GUI). The CLI is provisioned at
`~/.local/bin/obsidian`, and that directory is added to `PATH`; the desktop
application must be running for CLI commands to work. The private Electron
runtime is named `obsidian` internally so Obsidian's CLI registration check does
not see plain Electron, but that GUI executable is not exposed as the user-facing
`obsidian` command. The flake-locked runtime disables Obsidian's self-updater and
cleans user updater `.asar` artifacts during activation. On KDE, the desktop
bridge starts at login minimized with a taskbar entry so it can be restored. If
the desktop is already running during activation, Obsidian state synchronization
is deferred until a later activation rather than blocking the Home Manager
generation.

Hermes Desktop is enabled through
`home/yashindo/apps/hermes-desktop.nix`. It uses the upstream Home Manager
module's Nix-packaged desktop runtime and launcher, with no persistent Hermes
gateway, system service, container, custom dashboard token, or declarative
provider credentials. The Plasma taskbar pin is declared in
`home/yashindo/plasma/taskbar-panel.nix`. The Hermes flake input follows
upstream `main`, while `flake.lock` keeps each installed revision
reproducible until the next explicit flake update. Home Manager installs the
application and its Computer Use runtime dependencies, but Hermes owns the
writable `~/.hermes/config.yaml` and model selection.

Hermes' Computer Use dependency group is built into the Nix-managed Hermes
runtime. Because the Nix environment is immutable, Hermes' lazy-install
fallback is redirected to the user-writable dedicated cache
`~/.cache/hermes/computer-use-lazy`; the Desktop launcher exports that target
before Hermes bootstrap so optional SDK discovery does not try to write to
`/nix/store`. `uv`, AT-SPI, and the X11 input libraries are declared
systemwide; `cua-driver` remains a user-owned runtime prerequisite. Provider
credentials, Browser Use cloud authentication, and real-browser profile access
remain manual and private. The Hermes launcher explicitly selects native
Wayland for Electron and enables cua-driver's native Wayland backend; static
browser CDP endpoints are not configured. Plasma's KDE portal is preferred for
Wayland screen capture, with GTK as a fallback; the first screen-capture grant
remains user-owned portal permission state.

## Does Not Belong Here

| Category | Put It Here Instead |
| --- | --- |
| Bootloader and kernel | `hosts/` |
| Hardware and GPU drivers | `hosts/` or `modules/nixos/hardware/` |
| Docker daemon | `modules/nixos/virtualisation.nix` |
| KVM/libvirt and virt-manager | `modules/nixos/kvm-manager.nix` |
| Distrobox container declarations | `modules/nixos/development/` |
| Users and groups | `modules/nixos/users/` |
| System security settings | `modules/nixos/core/` |

The Home Manager profile also exposes the Nix-provided Docker Buildx plugin in
`~/.docker/cli-plugins/` so the pinned Compose package can discover it when
using Bake; activation remains a user-owned step.

## Toggle Pattern

App modules are imported and enabled from:

```text
home/yashindo/apps/default.nix
```

Plasma modules are imported and enabled from:

```text
home/yashindo/plasma/default.nix
```

This keeps each app file focused on configuration while the `default.nix` files act as control panels.

## Spotify Playback

The active profile uses the stock `pkgs.spotify` package from the flake's
pinned `nixpkgs` input. It is provisioned by
`home/yashindo/apps/spotify.nix` and provides the unmodified Spotify desktop
client.

The active profile also enables the stock `pkgs.spotifyd` package with its
original module settings and normal autoplay behavior. No GUI-first or
manual-only systemd override is applied. `spotify-player` remains disabled.
Running Spotify and spotifyd at the same time may make them compete for the
same account or audio device; stop one before handing playback to the other.
Existing Spotify caches and credentials are not removed automatically; activate
the new Home Manager generation as a user-owned step. Do not place Spotify
credentials in this repository.

Output selection and mute state remain user-owned PipeWire/WirePlumber state.
They are intentionally not hard-coded here, so Bluetooth, analog, HDMI, and
other sinks can be selected from the desktop session without a Home Manager
change.

## SOPS Build Toolchain

The locked `sops-nix` source requires Go 1.26 while stable nixpkgs keeps its
default Go and `buildGoModule` at 1.25. The Home Manager profile therefore
uses a local package set with `buildGo126Module` and `go_1_26` only for
`sops-install-secrets`; the system's default Go package remains unchanged.

## Peak-Hour Reminders

`home/yashindo/apps/peak-hours.nix` owns the weekday electricity-window
reminders. Peak hours are Monday to Friday, 09:00-12:00 and 14:00-18:00 in the
system's local time (Asia/Manila, no DST); every other hour, including weekends,
is off-peak, and holidays are not special-cased. The `peak-hours` command
reports the current state, renders the desktop widget, sends the current-state
notification, and prints the full schedule through `status`, `widget`, `notify`,
and `schedule`. The `widget` form emits rich text for the command output
plasmoid: an accent-coloured state line, the time to the next change, and a
progress bar for the current stretch, coloured from the Scarlet Tree night
wallpaper (comet cyan for off-peak, canopy scarlet for peak). Four user timers start
`peak-hours-notify.service` at 09:00, 12:00, 14:00, and 18:00 on weekdays so
each boundary is announced; the notification text is derived from the current
time, so a reminder that fires late (for example after resuming) describes the
window that is actually in effect. Each reminder repeats the widget's palette in
the notification body: a coloured state line above a lavender detail line, with
the matching badge installed from `home/yashindo/plasma/icons/` as
`peak-hours-offpeak` or `peak-hours-peak`. Notifications request a three-second
timeout, which Plasma honours for normal urgency. Setting `PEAK_HOURS_NOW` to
`"YYYY-MM-DD HH:MM"` pins the clock for tests.

The module also ensures the `com.github.zren.commandoutput` desktop widget from
`pkgs.plasma-applet-commandoutput` is present, showing the live state and the
time to the next change; hovering shows the schedule and clicking re-sends the
current-state notification. A desktop script creates the widget in the top-left
corner on first use and refreshes its command configuration, but never sets its
geometry afterwards: move the widget by pressing and holding it before dragging,
and Plasma keeps that position across reboots and rebuilds while other desktop
widgets stay untouched.

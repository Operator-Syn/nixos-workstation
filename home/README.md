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
| Apps | Brave, Google Chrome, Firefox, Discord, Obsidian, VS Code, Hermes Desktop |
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
(read-only) settings file.

General-purpose language runtimes such as Node and Python should usually stay out of `home/yashindo/packages.nix`. Prefer `devshells/` for project-scoped tooling and Distrobox for mutable dependency experiments.

The Obsidian module keeps the desktop launcher separate from Obsidian's native
Linux CLI. The CLI is provisioned at `~/.local/bin/obsidian`, while the desktop
entry uses an executable named `obsidian` so Obsidian's CLI registration check
does not identify the application as plain Electron. Obsidian's desktop process
also starts at login iconified and hidden from the taskbar, because the CLI
requires the desktop application to be running.

Hermes Desktop is enabled through
`home/yashindo/apps/hermes-desktop.nix`. It uses the upstream Home Manager
module's Nix-packaged desktop runtime and launcher, with no persistent Hermes
gateway, system service, container, custom dashboard token, or declarative
provider credentials. The Plasma taskbar pin is declared in
`home/yashindo/plasma/taskbar-panel.nix`. The Hermes flake input follows
upstream `main`, while `flake.lock` keeps each installed revision
reproducible until the next explicit flake update.

Hermes' optional Browser Use and Computer Use integrations use the host runtime
provided by Hiraeth's Nix configuration. `uv`, AT-SPI, and the X11 input
libraries are declared systemwide so the Hermes Desktop setup flow can install
the user-owned Browser Use CLI and `cua-driver` into `~/.hermes` and
`~/.cua-driver` after activation. Provider credentials, Browser Use cloud
authentication, and real-browser profile access remain manual and private.
The desktop uses the default XWayland path; native Wayland and static browser
CDP endpoints are not configured.

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

The active profile uses `ncspot`, a lightweight terminal Spotify client built
on the librespot library. It is provisioned from
`home/yashindo/apps/ncspot.nix` using the flake's pinned
`nixpkgs-unstable` input. The packaged build includes the PulseAudio backend,
which routes through Hiraeth's PipeWire-Pulse session. ncspot does not create a
user service or autostart entry; run `ncspot` in a terminal when playback is
wanted.

On first run, ncspot opens an OAuth flow in a browser and stores its
user-owned credentials in its cache. A Spotify Premium account is required.
See the [ncspot user documentation](https://github.com/hrkfdn/ncspot/blob/main/doc/users.md)
for the login and configuration flow. Do not place Spotify credentials in this
repository.

The legacy `spotify`, `spotify-player`, and `spotifyd` modules remain
available but disabled in the active profile. No official Spotify GUI,
spotify-player daemon, or spotifyd user service is generated. Existing Spotify
caches and credentials are not removed automatically; closing already-running
processes and activating the new Home Manager generation remain user-owned
steps.

Output selection and mute state remain user-owned PipeWire/WirePlumber state.
They are intentionally not hard-coded here, so Bluetooth, analog, HDMI, and
other sinks can be selected from the desktop session without a Home Manager
change.

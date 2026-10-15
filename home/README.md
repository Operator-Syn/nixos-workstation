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

`modules/nixos/packages.nix` owns the shared Git executable. `home/yashindo/apps/git.nix` configures Git to sign every commit with SSH,
using `~/.ssh/id_ed25519.pub`. Register that public key with GitHub as a
signing key. GitHub also associates a commit with its effective committer email;
stale repository-local `user.name` or `user.email` values override the global
identity. The global Git settings take effect after Home Manager activation;
they do not retroactively sign existing commits.

KWin's Blur effect is explicitly disabled in
`home/yashindo/plasma/desktop-settings.nix` while compositor offscreen-framebuffer
errors are being investigated; the other configured effects remain unchanged.

Global keyboard shortcuts have a semi-declarative starting point in
`home/yashindo/plasma/shortcuts.nix`. Two pieces must both be in place for a
starter binding to work:

| Piece | Location | Written by |
| --- | --- | --- |
| Action definitions | `~/.local/share/kglobalaccel/plasma-manager-commands.desktop` | Home Manager (`home.file`) |
| Starter bindings | `~/.config/kglobalshortcutsrc`, group `[services][plasma-manager-commands.desktop]` | Seeded by activation, then user-owned |

The desktop entry name matters: KGlobalAccelD discovers service components by
scanning `<data dir>/kglobalaccel/*.desktop` and maps each file's `Actions` to
shortcut actions. The same mechanism provides Spectacle's, Dolphin's and
Konsole's application shortcuts. Do not move this file back to
`share/applications` or generate it with `xdg.desktopEntries`; those publish it
as a profile package that KGlobalAccelD does not read for actions, which is why
an earlier declaration of these shortcuts never bound anything.

The starter actions are open Alacritty on `Ctrl+Shift+X` and toggle webcam
privacy on `Meta+Shift+C`. Each binding is seeded only when that action is
missing from the shortcut file. After the first activation, Plasma owns the
file: changing or clearing a starter binding in System Settings is not rewritten
by Home Manager. `programs.plasma.overrideConfig` remains disabled.

Bindings attach at session start, because KGlobalAccelD runs inside
`kwin_wayland` on this Plasma release and reads the component files once when it
starts. After the first activation that installs the desktop entry, log out and
back in. Until then the seeded keys exist in the file but are not attached to an
action, so pressing them does nothing.

To branch out without editing this repository, use Plasma System Settings →
Shortcuts → Global Shortcuts → Add New → Command or Script…. KDE stores the
action as a user-owned desktop file plus its binding in the shortcut
configuration; both survive reboots, Home Manager activations, and NixOS
rebuilds. Keep the starter module free of `programs.plasma.hotkeys`
declarations; that interface is declarative and rewrites every binding it
declares on each activation.

VS Code user settings, language-specific formatters, Nix language-server
configuration, terminal defaults, and trusted schema domains are declared in
`home/yashindo/apps/vscode.nix`. The module adds its formatter as a package and stores the absolute Nix-store path in both VS Code Nix formatter settings, so formatting does not depend on an ambient `PATH`. By default, the declared settings seed a
writable `~/.config/Code/User/settings.json`; imperative edits are retained
and take precedence over declarative defaults. Set
`modules.vscode.mutableUserSettings = false` for a fully Home Manager-managed
(read-only) settings file.
After repeated native-Wayland renderer `SIGILL` crashes, VS Code is configured
to launch through XWayland as a scoped mitigation. KDE itself remains on
Wayland. The package also adjusts the built-in Copilot extension's shim-copy
permissions so its files under writable user storage remain replaceable despite
the Nix-store source being read-only.
Rust Analyzer uses a Nix-managed launcher that
checks the current workspace's nearest `.envrc`. For an allowed environment,
it prefers the project's `rust-analyzer` and runs it with that environment; if
the environment has no Rust Analyzer binary, it runs the Nix-managed fallback
inside that environment. With no allowed `.envrc`, it uses the fallback
directly. The launcher never approves `.envrc` files; `direnv allow` remains an
explicit user action.

Fish autosuggestions use muted purple italics to distinguish the proposed
suffix from text already typed in VS Code and Alacritty terminals. The color
applies to new Fish sessions after Home Manager activation.

General-purpose language runtimes such as Node and Python should usually stay out of `home/yashindo/packages.nix`. Prefer `devshells/` for project-scoped tooling and Distrobox for mutable dependency experiments. Plasma provides its KDE graphics thumbnailers, and the enabled Home Manager EasyEffects service provides the app, so the user package list does not duplicate either declaration.

The desktop owns the writable `~/.config/mimeapps.list`, including browser,
folder, and app protocol associations. Home Manager does not generate that file:
desktop applications may update it during a session, so application defaults
must be set in the desktop on a new profile. Existing MIME preferences and
older backup files are not changed by this declaration.

LibreOffice uses nixpkgs' canonical `libreoffice-qt` package. The Prisma
module selects `prisma-engines_7` explicitly; in the pinned 26.05 package set,
these match the derivations previously reached through compatibility aliases.

Brave and Discord launch directly on the AMD integrated GPU with no
GPU-selection dialog. `home/yashindo/apps/brave.nix` keeps the package's own
desktop entry and `BROWSER=brave`, with no second-profile Brave Work launcher.
Discord's KDE login entry waits until DNS can resolve `discord.com`, then
starts minimized in the tray; manual launches through the package's application
entry or command remain immediate. The Nix package disables Discord's host updater so a delayed
nixpkgs update does not block startup; Discord's own module updates are
separate. `nvidia-offload` remains available from a terminal for dedicated-GPU
launches, and the Discord Professional module stays available but disabled.

NetBird's system daemon remains declared in `modules/nixos/netbird.nix`. The
Home Manager app module installs the matching tray UI and autostarts its
packaged desktop entry with the KDE session; this starts the interface at login
while leaving tunnel startup to the system service. Its Linux notifications request a three-second timeout without changing other applications. The UI override vendors and patches Wails, so its local `vendorHash` must be refreshed from the patched Go-module output when the locked NetBird version changes; the upstream proxy-vendor hash is not interchangeable.

The Obsidian module exposes `obsidian` (CLI), `obsidian-cli` (compatibility
name), and `obsidian-desktop` (GUI). The CLI is provisioned at
`~/.local/bin/obsidian`, and that directory is added to `PATH`; the desktop
application must be running for CLI commands to work. The desktop
launcher runs through NixOS's `nvidia-offload` helper and leaves Electron GPU
rendering enabled, requesting PRIME offload to NVIDIA on Hiraeth. The private
Electron runtime is named `obsidian` internally so Obsidian's CLI registration check does
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

Local Mnemosyne embedding generation is also packaged in this shared CLI/Desktop
Python runtime. The module uses the exact Hermes interpreter's Nix `fastembed`
and `numpy` packages (including ONNX Runtime), appended through a site-packages
`.pth` file so sealed Hermes packages retain precedence. Mnemosyne has no
upstream dependency group, and the upstream `extraPythonPackages` hook only
extends CLI `PYTHONPATH` and rejects shared-package collisions; this local
composition also covers Desktop and isolated Python subprocesses. The external
provider venv, its plugin files, and memory databases are not changed by this
embedding dependency addition. Model downloads remain in Mnemosyne's writable
cache. Activation and a Hermes restart are user-owned prerequisites for live
use; existing memories are not automatically migrated or backfilled.

The shared package also carries a small source patch that extends the external
provider's argparse tree with `hermes mnemosyne reindex`; it does not install a
second `hermes` launcher or edit the provider venv. This is a local adapter for
Mnemosyne 3.15.1, not a Hermes upstream command. Existing subcommands stay with
the provider, and a future native `reindex` takes precedence. Re-test the adapter
when updating either Hermes or the external provider.

Embedding-model selection needs one provider-side adjustment that the `.pth`
composition cannot make on its own. The provider reads
`MNEMOSYNE_EMBEDDING_MODEL` and `MNEMOSYNE_EMBEDDING_DIM` only at import time, and
Mnemosyne's own config loader classes those keys as `REQUIRES_RESTART`, so a model
configured in Hermes `config.yaml` or in `mnemosyne/config.yaml` never reaches an
imported module. Recall and every new vector then fall back to the package default
(`BAAI/bge-small-en-v1.5`, 384-dim), which against a store built at 768-dim fails
dense recall with a dimension mismatch and stores vectors the vec tables cannot
accept. `home/yashindo/apps/hermes/` therefore tracks
`mnemosyne-embedding-env-bridge.patch` and `embedding_env_bridge.py`; activation
installs the module beside the provider and applies the patch to the provider's two
entry-point files — `__init__.py` for the in-process provider and `cli.py` for
`hermes mnemosyne`, which do not import each other. This is the one exception to
"the provider venv is not changed": those two files are edited, not the provider
package and not its databases. The step is sentinel-guarded because it edits
mutable state on every activation, and it runs after the path-order step whose
`sys.path.append` rewrite forms the patch context. If the patch cannot apply after
a provider upgrade, activation warns rather than failing; dense recall then embeds
at the package default until the patch is refreshed. Activation and a Hermes
restart remain user-owned, and the live model is only proven by a recall that
returns hits rather than a dimension error.

`hermes mnemosyne reindex --dry-run` reports the resolved database, active model,
dimension and working/episodic counts through a read-only SQLite connection,
without initializing/migrating the provider or creating a missing database.
Routing follows the provider's config precedence, profile-isolation bank name,
`HERMES_HOME` and `MNEMOSYNE_DATA_DIR`; it never implicitly reindexes the shared
surface or every bank. `--model NAME` affects only this process and does not
save configuration. The preview does not load/test embedding weights.

A real rebuild requires all writers to that database to be stopped **by the
operator** first. The command warns and asks for confirmation; EOF or anything
other than yes cancels before backup/write. `--yes` explicitly acknowledges the
offline requirement, but does not stop services or prove no writer is running.
An owner-only SQLite backup named `mnemosyne.db.reindex-*.backup` is always made
beside the exact target and integrity-checked before writing. There is no
`--no-backup` bypass. The core API commits per batch: failure can leave a partial
rebuild. Errors/incomplete coverage exit nonzero and retain the backup; verify
recovery before restarting writers. Reindex rebuilds working/episodic vectors
and resets the unused facts-vector table, not source memory text or IDs.

Candidate-only verification (no activation or real-memory rebuild):

```sh
nix build .#nixosConfigurations.nixos.config.home-manager.users.yashindo.programs.hermes-agent.package --no-link --print-out-paths
nix eval --raw .#nixosConfigurations.nixos.config.home-manager.users.yashindo.programs.hermes-agent.package.hermesVenv
pipenv run python -m unittest discover -s tests -p test_mnemosyne_reindex.py
pipenv run python scripts/test_hermes_mnemosyne_reindex.py \
  <candidate>/bin/hermes <candidate-venv>/bin/python3 \
  <external-site-packages>/hermes_memory_provider <populated-fastembed-cache>
```

The integration harness creates its own home, configs, banks and databases under
`TMPDIR`, copies only embedding weights, and verifies actual local vectors,
source preservation, backups, preview/cancellation, failure codes and profile
routing. It accepts no input memory database. Add new repository source files to
Git's index (intent-to-add is sufficient) before a Git-flake build so Nix can see
them. Building/testing a candidate does not change the installed CLI; activation
and restarts remain separate user-owned operations.

The Nix-wrapped CLI treats its sealed Python environment and PATH tools as
externally managed. Gateway unit refreshes invoke the store Python directly,
without writing launchers into `/nix/store` or running Hermes PM reconciliation
for tools supplied by Nix. Gateway installation and service state remain
user-owned and are not activated by this module.

Hiraeth's NixOS package set also declares the host binaries Hermes Bot Screen
needs. Once that system generation is activated, Hermes can detect TigerVNC,
the minimal Xfce components, and its X11 helpers without using a distro package
manager. Hermes starts the profile's desktop on demand and uses a private Unix
socket; the separate Chromium browser dock is optional and is not installed by
this screen support.

Hermes' Computer Use dependency group is built into the Nix-managed Hermes
runtime. Because the Nix environment is immutable, Hermes' lazy-install
fallback is redirected to the user-writable dedicated cache
`~/.cache/hermes/computer-use-lazy`; the Desktop launcher exports that target
before Hermes bootstrap so optional SDK discovery does not try to write to
`/nix/store`. `uv`, AT-SPI, and the X11 input libraries are declared
systemwide. The built-in browser uses Hermes PM's pinned `agent-browser` CLI and
Chromium; Nix declares their required system libraries. The Hermes launcher
points Hermes at the existing user-owned `~/.local/bin/cua-driver`, and Hermes
PM keeps the browser tools in user-owned state. A Home Manager desktop entry,
`Hermes Browser (CDP)`, launches Google Chrome with the persistent full copy
at `~/.config/google-chrome-agent` and remote debugging bound to
`127.0.0.1:9222`. The copied Chrome state includes the source profile's cookies,
sessions, settings, and extensions; the source `~/.config/google-chrome`
directory remains untouched. Changes stay in the copy except for data Chrome
Sync may propagate. Hermes root configuration uses
`browser.backend: off`, `browser.use_real_profile: false`, and the stable CDP
base `ws://127.0.0.1:9222`; start Chrome from the launcher before connecting when
the endpoint is closed. The launcher refuses to create a blank profile if the
copy is missing.
The Browser Use CLI is installed through Hermes' package manager and can be
selected as an alternate mode; it replaces the built-in `browser` and
`browser-cdp` toolsets while selected. Doctor reports this expected mode
selection as inactive instead of a missing system dependency. The A2A platform
is enabled for inbound localhost use on `127.0.0.1:9900`; outbound peers and
remote inbound access are not configured. Gateway installation, restart, and
service state remain user-owned. Provider credentials and Browser Use cloud
authentication remain manual and private. The generated Hermes Desktop launcher
exports the CDP and loopback A2A endpoints; these launcher and desktop-entry
changes take effect after Home Manager activation. The Hermes launcher
explicitly selects native Wayland for Electron and enables cua-driver's native
Wayland backend. It sets `HERMES_DESKTOP_NVIDIA_SWIFTSHADER=0` because Hermes'
NVIDIA 580+ driver guard would otherwise route ANGLE through SwiftShader even
with the AMD integrated GPU selected. This keeps rendering on the AMD hardware
path without forcing NVIDIA PRIME offload; the change takes effect after Home
Manager activation and restarting Hermes Desktop. The packaged renderer also
reuses a live assistant bubble if a transcript refresh replaces its local
stream ID, and rebases an unsent message onto newer stored history before
submitting it. Plasma's KDE portal is preferred
for Wayland screen capture, with GTK as a fallback; the first screen-capture
grant remains user-owned portal permission state.

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

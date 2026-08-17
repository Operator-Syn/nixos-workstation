# BedrockOnLinux on NixOS

This directory owns the Nix package and NixOS module for
[BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux).

The package contains the upstream Python/Tk launcher, its Python dependencies,
the desktop entry, and icon. It does not put the Minecraft game,
WineGDK/Proton, or UMU in the Nix store. On first use, the launcher downloads
and verifies the Windows game and its runtime into the per-user BedrockOnLinux
data directory. The immutable launcher is placed inside Nixpkgs' official
`steam.buildRuntimeEnv` FHS boundary because UMU/pressure-vessel requires
standard `/usr/bin`, `ldconfig`, and multi-architecture runtime paths. UMU
then supplies its own SteamLinuxRuntime/pressure-vessel boundary inside that
outer NixOS compatibility environment. Do not invoke the inner store package
directly or add another `steam-run` layer.

## Host configuration

The Hiraeth host imports this module and enables it with:

```nix
modules.bedrock-on-linux.enable = true;
```

To review the package without activating the system configuration:

```sh
nix build ~/nix-config#bedrock-on-linux
```

After reviewing a system generation, use the repository's `rebuild` helper (or
the equivalent `nixos-rebuild` command) to activate the package. Building or
evaluating the flake does not change the running system. Confirm the active
generation before testing:

```sh
readlink -f "$(command -v bedrock-on-linux)"
bedrock-on-linux doctor
```

The `doctor` output must show `pillow/QR : OK (GUI)`. If it reports the old
environment or `PIL` is missing, the new generation has not been activated.

## First run

Launch the graphical setup:

```sh
bedrock-on-linux gui
```

The launcher requires an owned Minecraft Bedrock for Windows installation. The
usual command flow is:

```sh
bedrock-on-linux doctor
bedrock-on-linux versions
bedrock-on-linux setup
bedrock-on-linux login
bedrock-on-linux play
```

The exact setup and login prompts are controlled by the upstream launcher.
Keep worlds backed up before changing or repairing a game installation.

### Microsoft device-code sign-in

When the launcher shows the sign-in dialog, the QR code is generated locally
by the launcher. Scan it with a phone, or select **Open Microsoft sign-in
page** and enter the displayed code. If the browser button is unavailable, open
the Microsoft device-code page directly at:

```text
https://www.microsoft.com/link
```

Enter the code shown in the launcher there. Device codes are temporary and
must not be reused or shared. A `too many attempts` message on the first
visible try is generally Microsoft-side throttling or a stale/rejected device
code, not a missing Python module. Close or cancel the dialog, wait for the
Microsoft cooldown, and start one fresh sign-in flow. Repeatedly submitting the
same code can extend the cooldown.

The Nix package includes Pillow, which the launcher needs to render that QR
code. Its build check and `doctor` check import Tk, CustomTkinter, Pillow, and
the bundled QR encoder. `PIL: missing — ModuleNotFoundError` therefore means
the active system generation is stale or a different launcher is being run;
build and activate the updated generation, then confirm the executable path
before testing sign-in again.

## Runtime requirements and GPU notes

The upstream runtime currently targets x86-64 Linux, X11/XWayland, and a Vulkan
1.3-capable GPU with the required device-generated-commands extension. Hiraeth's
existing Steam and graphics modules provide the normal desktop prerequisites.

The default path is X11/XWayland. Wayland input can be tested with:

```sh
BOL_INPUT=wayland bedrock-on-linux gui
```

For an NVIDIA PRIME offload session, the host helpers can be used when needed:

```sh
nvidia-offload bedrock-on-linux gui
nvrun bedrock-on-linux gui
```

Hiraeth loads the kernel's `ntsync` module for Wine's in-process
synchronization. If another host uses a kernel that provides the module,
load it with `sudo modprobe ntsync` before launching; without `/dev/ntsync`,
Wine falls back to slower wineserver synchronization.

If the launcher or game reports a GPU fault, run `bedrock-on-linux doctor` and
inspect the current boot journal before trying workarounds. Do not enable
`BOL_ALLOW_UNSAFE_GPU=1` as a routine fix; it bypasses a safety check rather
than repairing the driver or kernel path.

## User data and isolation

BedrockOnLinux stores downloaded game and runtime data below:

```text
~/.local/share/bedrock-on-linux/
```

For a separate test installation, set `BOL_HOME` before launching the program:

```sh
BOL_HOME=/path/to/test-bedrock bedrock-on-linux gui
```

This data is intentionally mutable and is separate from the immutable Nix
package. The launcher may report that updates should be performed by the Nix
package manager; that is expected for a read-only Nix installation.

## Updating the launcher

The flake tracks the upstream repository as a source-only input. It can be
updated without pinning the package to a hand-written version:

```sh
nix flake update bedrock-on-linux --flake ~/nix-config
nix flake check --no-build --show-trace
```

Review the lockfile and build the package before activating the resulting
system generation.

## Diagnostics

Useful commands include:

```sh
bedrock-on-linux doctor --network
bedrock-on-linux doctor
bedrock-on-linux repair
bedrock-on-linux import
```

`bedrock-on-linux repair` resets the managed `compatdata` Wine prefix; it does
not redownload the game, WineGDK, or UMU runtime. Back up worlds first, then
run `repair` and **Install / Update** again when the prefix has no valid
`system.reg` and `user.reg` files. The existing prefix failure is at that
initialisation boundary, before GameInput installation.

If `native-login.log` contains `bwrap: execvp true: No such file or directory`
or a missing Nix `ld.so.cache`, confirm that the active command resolves to the
new FHS-wrapped generation before repairing the prefix:

```sh
readlink -f "$(command -v bedrock-on-linux)"
bedrock-on-linux doctor
```

If sign-in fails, open the launcher **Details** panel after the attempt. The
updated package reports rate-limit, expired-code, and other Microsoft errors
there and resets the account button so a new flow can be started cleanly.

`repair` addresses launcher-managed downloads and prefixes; it does not repair
the host's kernel, Vulkan driver, ASUS controls, or GPU power-management
configuration. The launcher and game remain subject to their upstream and
third-party licenses. You must own the required Minecraft license and comply
with the terms of the downloaded components.

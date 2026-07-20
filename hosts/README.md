# Hosts

Concrete machine configurations live here.

A host represents one physical or virtual NixOS system with its own hardware scan, boot setup, hostname, GPU settings, and selected system modules.

---

## Current Host

| Host | Flake Output | Purpose |
| --- | --- | --- |
| `hiraeth` | `nixosConfigurations.nixos` | Main NixOS machine |

## Layout

```text
hosts/
`-- hiraeth/
    |-- default.nix                 host entry point
    |-- boot.nix                    kernel and bootloader settings
    |-- hardware-configuration.nix  generated hardware scan
    |-- storage.nix                 host storage declarations
    `-- nvidia.nix                  NVIDIA and graphics configuration
```

## Host Responsibilities

| Area | Examples |
| --- | --- |
| Identity | hostname, host-specific module toggles |
| Boot | GRUB, EFI, kernel package |
| Hardware | generated hardware scan, filesystems, CPU microcode |
| Graphics | GPU bus IDs, NVIDIA mode, PRIME/offload settings |
| Imports | selecting reusable modules from `modules/nixos/` |
| Services | Hermes, Graphify, Obsidian vault, NetBird, ACL reconciliation |

## Enabled Development Support

`hiraeth` currently uses Docker-backed Distrobox for dirty dependency experiments:

```nix
modules.distrobox.debian-dev.enable = true;
```

The old Docker-managed Debian container module remains disabled. The system-level Python shell module is enabled for Hiraeth, while project-specific Python environments remain available through `devshells/`.

The Debian Distrobox uses `/bin/bash` as its container shell so it does not try to launch the host NixOS `fish` binary inside Debian.

After switching the system, create the declared Debian box once:

```sh
assemble-debian-dev
```

Then enter it when needed:

```sh
distrobox enter debian-dev
```

## Boundary

Keep values here when they are specific to this machine.

Move logic into `modules/nixos/` when it could reasonably be reused by another host.

## Hardware Refresh

The generated hardware file is:

```text
hosts/hiraeth/hardware-configuration.nix
```

The `update-hardware` helper targets that path.

Review changes carefully before committing, especially anything involving filesystems, boot devices, or swap.

## Switching This Host

The fish alias `rb` runs the repository rebuild helper, including the hardware scan and post-activation ACL reconciliation request:

```sh
rb
```

For a direct activation without the helper:

```sh
sudo nixos-rebuild switch --flake ~/nix-config#nixos --cores "$(nproc)" --show-trace
```

After activation, verify the live generation separately:

```sh
systemctl --failed
systemctl status home-acl-reconcile.service --no-pager
```

Hiraeth's ACL direction is intentionally asymmetric. The `feilhann-home-admin`
group contains only `yashindo` and grants Yashindo full access to Feilhann's
home. The reverse permissions are limited to Feilhann's read-only audit view of
Yashindo's home, excluding `Git`, plus the separate Feilhann Git write policy.
The ACL reconciler applies these declarations after tmpfiles resetup.

## Hiraeth ASUS and NVIDIA Compatibility

Hiraeth is an ASUS TUF Gaming A16 FA607NUQ with AMD integrated graphics and
an NVIDIA RTX 4050-class discrete GPU. Its ASUS Armoury controls require the
newer kernel package set, while the proprietary NVIDIA module pairing used by
the stable kernel does not provide a compatible Armoury-capable generation.

The host therefore uses `pkgsUnstable.linuxPackages_latest` together with
`hardware.nvidia.open = true` and the matching latest NVIDIA package from that
kernel package set. Both the `asus-armoury` module and the NVIDIA modules must
be present in the built generation before switching to it.

Before activation, verify the candidate generation contains:

```text
asus-armoury.ko
nvidia.ko
nvidia-modeset.ko
nvidia-drm.ko
nvidia-uvm.ko
```

Keep the previous stable generation in GRUB until `modinfo asus-armoury`,
`nvidia-smi`, `asusctl`, and ROG Control Center have been verified after a
reboot.

### Control boundaries

Hiraeth uses native Linux controls on NixOS:

```text
asus-armoury -> asusd/asusctl + ROG Control Center
supergfxd    -> manual Integrated, Hybrid, or MUX GPU mode changes
NVIDIA PRIME -> per-application dGPU rendering in Hybrid mode
Plasma PPD   -> Silent, Balanced, and Performance platform profiles
```

G-Helper is a Windows-only application that relies on the Windows ASUS System
Control Interface driver. Use it only from the Windows installation; do not
run it through Wine or a virtual machine on NixOS.

Keep GPU-mode changes manual. Before changing Integrated or MUX mode, record
the active NixOS generation and verify Hybrid mode, internal and external
displays, `nvidia-offload`, and suspend/resume. If graphics fail after a mode
change, boot the previous GRUB generation and return to Hybrid mode before
trying another change.

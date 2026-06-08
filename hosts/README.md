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

## Enabled Development Support

`hiraeth` currently uses Docker-backed Distrobox for dirty dependency experiments:

```nix
modules.distrobox.debian-dev.enable = true;
```

The old Docker-managed Debian container module and system-level Python shell module are left disabled in `hosts/hiraeth/default.nix`.

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

```sh
sudo nixos-rebuild switch --flake ~/nix-config#nixos --cores "$(nproc)" --show-trace
```

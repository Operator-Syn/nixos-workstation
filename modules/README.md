# NixOS Modules

Reusable system-level modules live here.

These files describe behavior that can be imported by hosts. The `Hiraeth` host currently imports modules from `modules/nixos/` through `hosts/hiraeth/default.nix`.

---

## Layout

```text
modules/
`-- nixos/
    |-- core/             locale, Nix settings, security, zram
    |-- desktop/          Plasma, audio, printing, display manager
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
| `core/` | Nix settings, locale, sudo, polkit, zram |
| `desktop/` | Plasma 6, SDDM, PipeWire, printing, XKB |
| `development/` | Distrobox setup, declared mutable boxes, optional Python support, containers |
| `hardware/` | Bluetooth and reusable ASUS hardware support |
| `users/` | system users, shells, groups |
| `bedrock-on-linux/` | BedrockOnLinux launcher package and NixOS module |
 | `netbird.nix` | NetBird VPN client |
| `ollama.nix` | optional local Ollama service; currently not enabled by Hiraeth |
| `openssh.nix` | OpenSSH server with password and root login disabled |
| `packages.nix` | system-wide packages |
| `scripts.nix` | `rebuild`, `update-system`, `update-codex`, `update-hardware`, `wifi-hotspot`, `nvrun`, `getGPU` |
| `steam.nix` and `steam/` | Steam, GameMode, gamescope, launchers, and Protontricks support |
| `kvm-manager.nix` | KVM/libvirt services, default network startup, and virt-manager |
| `virtualisation.nix` | Docker service |

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
| `development/python-shell.nix` | Optional system-level Python shell support, enabled on `hiraeth` |

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

## Hiraeth ASUS Controls

`hardware/asus.nix` owns the native Linux ASUS stack: `asusd`,
`asusctl`, ROG Control Center, and `supergfxd`. Keep host-specific kernel and
NVIDIA PRIME settings in `hosts/hiraeth/`.

KDE Plasma's `power-profiles-daemon` owns the generic platform profile. ASUS
controls remain responsible for firmware-specific features such as charge
thresholds, keyboard lighting, fan curves, and Armoury features. Do not add
Windows G-Helper, Wine, or a second GPU-switching daemon to this stack.

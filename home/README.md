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
| Apps | Brave, Google Chrome, Firefox, Discord, Obsidian, VS Code |
| User packages | fonts, utilities, creative tools |
| Desktop preferences | Plasma panels, colors, wallpaper, icons |
| User services | app-level user services and autostart entries |

General-purpose language runtimes such as Node and Python should usually stay out of `home/yashindo/packages.nix`. Prefer `devshells/` for project-scoped tooling and Distrobox for mutable dependency experiments.

The Obsidian module keeps the desktop launcher separate from Obsidian's native
Linux CLI. The CLI is provisioned at `~/.local/bin/obsidian`, while the desktop
entry uses an executable named `obsidian` so Obsidian's CLI registration check
does not identify the application as plain Electron. Obsidian's desktop process
also starts at login iconified and hidden from the taskbar, because the CLI
requires the desktop application to be running.

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

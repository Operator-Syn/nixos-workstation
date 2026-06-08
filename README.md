# Nix Config

A personal NixOS flake for the `Hiraeth` machine and the `yashindo` Home Manager profile.

This repo is meant to be readable first: each folder owns one layer of the system, and the main flake keeps those layers wired together.

---

## At A Glance

| Area | Purpose | Main Entry |
| --- | --- | --- |
| `hosts/` | Machine-specific NixOS configuration | `hosts/hiraeth/default.nix` |
| `modules/` | Reusable system modules | `modules/nixos/` |
| `home/` | User-level Home Manager configuration | `home/yashindo/default.nix` |
| `devshells/` | Reusable project environments | `devshells/default.nix` |
| `flake.nix` | Flake inputs, outputs, system wiring | `flake.nix` |

## Repository Map

```text
.
|-- devshells/       reusable nix develop environments
|-- home/            Home Manager profile and desktop config
|-- hosts/           concrete machine configurations
|-- modules/         reusable NixOS system modules
|-- flake.nix        main flake entry point
`-- flake.lock       pinned input revisions
```

## Command Deck

| Task | Command |
| --- | --- |
| Format Nix files | `nix fmt` |
| Evaluate the flake | `nix flake check --no-build --show-trace` |
| Switch system | `sudo nixos-rebuild switch --flake ~/nix-config#nixos --cores "$(nproc)" --show-trace` |
| Enter default dev shell | `nix develop ~/nix-config` |
| Enter Node dev shell | `nix develop ~/nix-config#node` |
| Enter Python + Playwright shell | `nix develop ~/nix-config#python-playwright` |
| Create declared Debian Distrobox | `assemble-debian-dev` |
| Enter Debian Distrobox | `distrobox enter debian-dev` |

## How The Layers Fit

```text
flake.nix
  |
  |-- nixosConfigurations.nixos
  |     `-- hosts/hiraeth
  |           |-- host files
  |           `-- modules/nixos/*
  |
  |-- home-manager.users.yashindo
  |     `-- home/yashindo
  |
  `-- devShells.x86_64-linux
        `-- devshells/default.nix
```

## Working Rules

- Keep machine-specific values in `hosts/`.
- Keep reusable system behavior in `modules/nixos/`.
- Keep user-session behavior in `home/`.
- Keep project tools in `devshells/` before installing them globally.
- Keep mutable throwaway development boxes in Distrobox manifests, not global packages.
- Keep `system.stateVersion` and `home.stateVersion` pinned unless intentionally migrating stateful defaults.

## Development Environments

Project language runtimes live in `devshells/`. Use `nix develop ~/nix-config#node` for Node/npm/pnpm/bun projects and `nix develop ~/nix-config#python` for Python projects.

For messy experiments that should behave more like a small mutable VM, `hiraeth` enables a Docker-backed Distrobox setup. The Debian box is declared in `modules/nixos/development/distrobox-debian-dev.nix`, but it is created manually so rebuilds do not wipe or recreate it:

```sh
assemble-debian-dev
distrobox enter debian-dev
```

The Debian box uses `replace=false`, so packages installed inside it with `apt`, `pip`, `npm`, or other tools persist until the container is removed.

## Git And Flakes

Nix flakes read from the Git tree. When adding new files that the flake imports, stage them before evaluating:

```sh
git add path/to/new-file.nix
nix flake check --no-build --show-trace
```

Untracked files can appear missing to Nix, even when they exist on disk.

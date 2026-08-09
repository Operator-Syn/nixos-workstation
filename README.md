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
| `mcp/` | Repository-scoped Project MCP and contract tests | `mcp/src/server.ts` |
| `scripts/` | Graphify and repository helper scripts | `scripts/rebuild_graphify.sh` |
| `tests/` | Python helper and integration tests | `tests/` |
| `Pipfile` / `Pipfile.lock` | Locked Graphify and Python test environment | `pipenv` |
| `package.json` / `bun.lock` | Project MCP runtime and Bun tests | `bun` |
| `flake.nix` | Flake inputs, outputs, system wiring | `flake.nix` |

## Repository Map

```text
.
|-- devshells/       reusable nix develop environments
|-- home/            Home Manager profile and desktop config
|-- hosts/           concrete machine configurations
|-- modules/         reusable NixOS system modules
|-- mcp/             repository-scoped Project MCP
|-- scripts/         Graphify and repository helpers
|-- tests/           Python test suite
|-- flake.nix        main flake entry point
`-- flake.lock       pinned input revisions
```

## Command Deck

| Task | Command |
| --- | --- |
| Format Nix files | `nix fmt` |
| Evaluate the flake | `nix flake check --no-build --show-trace` |
| Build the Hiraeth system | `nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel` |
| Run the canonical rebuild workflow | `rb` |
| Run the rebuild helper directly | `rebuild` |
| Update flake inputs and rebuild | `update-system` |
| Refresh hardware configuration only | `uh` |
| Direct low-level system switch | `sudo nixos-rebuild switch --flake ~/nix-config#nixos --cores "$(nproc)" --show-trace` |
| Enter default dev shell | `nix develop ~/nix-config` |
| Enter Node dev shell | `nix develop ~/nix-config#node` |
| Enter Python + Playwright shell | `nix develop ~/nix-config#python-playwright` |
| Test the Project MCP | `bun run mcp:test` |
| Test Python helpers | `pipenv run python -m unittest discover -s tests` |
| Query the repository graph | `pipenv run graphify query "your question"` |
| Refresh the incremental graph | `pipenv run graphify update .` |
| Create declared Debian Distrobox | `assemble-debian-dev` |
| Enter Debian Distrobox | `distrobox enter debian-dev` |

`rb` is the canonical Fish alias for the system-wide `rebuild` helper. It refreshes the hardware configuration and activates the NixOS generation. Use `rebuild` directly from another shell, `update-system` to update flake inputs before rebuilding, or `uh`/`update-hardware` when only the hardware scan is needed. The direct `nixos-rebuild` command above is a low-level fallback that bypasses the custom hardware refresh. Activation is still user-owned and should be followed by live checks such as `systemctl --failed` and `docker ps`.

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

## Project MCP

This repository provides a local stdio MCP server for repository-aware NixOS work. It can inspect the flake, prepare isolated patches, apply explicitly approved file changes, validate the flake, and create separately approved one-file commits. It cannot run privileged system activation or arbitrary shell commands. See [`mcp/README.md`](mcp/README.md) for the authority model and setup.

The Project MCP also exposes read-only authority and declarative-contract checks. They enforce the distinction between repository changes prepared by an agent and live NixOS activation performed by the user. Built configuration and Graphify output are evidence, not substitutes for live verification.

The read-only `read_authority_contract` tool describes this boundary, while `validate_declarative_contract` checks the repository source for declarative configuration and safe MCP command boundaries. These checks do not inspect live `/run`, user homes, credentials, or the protected vault.

The MCP may inspect the repository, prepare patches, apply explicitly approved patches, validate the flake, and create explicitly approved one-file commits. Users retain ownership of `sudo`, `rb`/NixOS activation, reboot, systemd checks, and live permission verification.

## Project Graphify

Graphify is available as a Pipenv-managed, read-only discovery MCP alongside the project MCP. Install the locked environment with `pipenv install --deploy`, then rebuild the graph and add the repository-local Nix relationships with:

```sh
./scripts/rebuild_graphify.sh
```

The script performs a forced full extraction so older pre-`#1504` node IDs are replaced, merges the Nix adapter output, and exports HTML. Query it with `pipenv run graphify query "your question"`. Graph output stays in the ignored `graphify-out/` directory, and `.graphifyignore` excludes secrets and assistant configuration. The Nix adapter records source-level imports, flake wiring, and `inputs.<name>` usage without evaluating the flake; Nix remains authoritative and is validated with `nix flake check`.

Graphify is for discovery only. It must not be used to mutate Nix source, ACLs, credentials, or vault plans. Run `pipenv run graphify update .` after source changes when the graph should be refreshed without a full extraction.

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

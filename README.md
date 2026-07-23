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
| `scripts/` | Graphify, audit, and repository helper scripts | `scripts/rebuild_graphify.sh` |
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
|-- scripts/         audit and Graphify helpers
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
| Run the repository rebuild workflow | `rb` |
| Switch system | `sudo nixos-rebuild switch --flake ~/nix-config#nixos --cores "$(nproc)" --show-trace` |
| Enter default dev shell | `nix develop ~/nix-config` |
| Enter Node dev shell | `nix develop ~/nix-config#node` |
| Enter Python + Playwright shell | `nix develop ~/nix-config#python-playwright` |
| Test the Project MCP | `bun run mcp:test` |
| Test Hermes and Graphify helpers | `pipenv run python -m unittest discover -s tests` |
| Query the repository graph | `pipenv run graphify query "your question"` |
| Refresh the incremental graph | `pipenv run graphify update .` |
| Create declared Debian Distrobox | `assemble-debian-dev` |
| Enter Debian Distrobox | `distrobox enter debian-dev` |

`rb` is the fish alias for the repository's `rebuild` helper. It scans hardware, activates the NixOS generation, and starts the unified ACL reconciliation service. Activation is still user-owned and should be followed by live checks such as `systemctl --failed`, `systemctl status home-acl-reconcile.service --no-pager`, and targeted `getfacl` checks.

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

The Project MCP also exposes read-only authority and declarative-contract checks. They enforce the distinction between repository changes prepared by an agent and live NixOS activation performed by the user. In particular, ACLs are declared in Nix, write access uses dedicated groups and administrator ACLs, read-only audit access stays separate, and one locked `home-acl-reconcile` service remains the canonical reconciliation path. Path-triggered watcher services provide faster self-healing for scoped project trees. Built configuration and Graphify output are evidence, not substitutes for live verification.

The read-only `read_authority_contract` tool describes this boundary, while `validate_declarative_contract` checks the repository source for the unified ACL service and timer, global locking, policy ordering, Git exclusions, Hermes managed mode, backend group membership, and safe MCP command boundaries. These checks do not inspect live `/run`, user homes, credentials, or the protected vault.

The MCP may inspect the repository, prepare patches, apply explicitly approved patches, validate the flake, and create explicitly approved one-file commits. Users retain ownership of `sudo`, `rb`/NixOS activation, reboot, systemd checks, and live permission verification.

## Declarative ACL And Hermes Boundaries

Home and project permissions are reconciled declaratively by `home-acl-reconcile.service` and its single persistent timer. The service takes a global lock and applies policies in a fixed order. `feilhann-home-admin` gives only `yashindo` full read-write access to the entire `/home/feilhann` tree, including hidden state and future files. Explicit administrator ACLs also preserve Yashindo's operational access to Feilhann-created content under `/home/yashindo/Git` and `/home/yashindo/nix-config`, plus the full `/srv/obsidian/hermes-vault` tree. The existing reverse policies remain separate: Feilhann receives read-only audit access to Yashindo's home with `Git` excluded, and retains dedicated read-write access to Yashindo's `Git` tree. `rb` is the repository rebuild workflow, but a successful build or activation does not replace live service and permission checks.

Hermes uses `/etc/hermes` for managed configuration. Yashindo's operating-system ACL access to Feilhann's private Hermes state and the shared vault does not expand the Project MCP authority: MCP still cannot read or mutate `/home/feilhann/.hermes/`, credentials, or vault plans. The working plans under `/home/feilhann/.hermes/plans/` and the protected shared-vault plan copies under `/srv/obsidian/hermes-vault/40 Plans/` are separate authority domains and are not automatically synchronized or made writable by MCP.

## Project Graphify

Graphify is available as a Pipenv-managed, read-only discovery MCP alongside the project MCP. Install the locked environment with `pipenv install --deploy`, then rebuild the graph and add the repository-local Nix relationships with:

```sh
./scripts/rebuild_graphify.sh
```

The script performs a forced full extraction so older pre-`#1504` node IDs are replaced, merges the Nix adapter output, and exports HTML. Query it with `pipenv run graphify query "your question"`. Graph output stays in the ignored `graphify-out/` directory, and `.graphifyignore` excludes secrets and assistant configuration. The Nix adapter records source-level imports, flake wiring, and `inputs.<name>` usage without evaluating the flake; Nix remains authoritative and is validated with `nix flake check`.

Graphify is for discovery only. It must not be used to mutate Nix source, ACLs, Hermes state, credentials, or vault plans. Run `pipenv run graphify update .` after source changes when the graph should be refreshed without a full extraction.

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

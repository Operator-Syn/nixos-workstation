# Project MCP

This repository includes a local, project-scoped MCP server for safe NixOS configuration work.

## Start it

The tracked `.codex/config.toml` entry starts the server through Bun when Codex opens this repository. For a direct local check:

```sh
bun mcp/src/server.ts
```

The server communicates through stdio and does not listen on a network port.

Graphify is a separate read-only MCP for repository discovery. Its Python environment is managed by Pipenv from `Pipfile.lock`; it does not grant Graphify patch, validation, or commit authority. Rebuild the graph, add the repository-local static Nix relationships, and generate HTML with:

```sh
./scripts/rebuild_graphify.sh
```

The rebuild script forces a full extraction to replace stale graph IDs, runs the Nix adapter, and exports HTML. Then query it with `pipenv run graphify query "your question"`. Nix evaluation remains authoritative; run `nix flake check` separately to validate the configuration.

## Authority model

- Read tools inspect the repository, Nix flake, and Git state.
- Prepare tools work in a temporary copy and return an operation ID, approval hash, exact file hashes, and a diff. They do not modify the real checkout.
- Apply tools require the returned operation ID and approval hash. They re-check every original file hash before writing.
- Git commits require a separate commit request, one file per commit, sentence-style messages ending in a period, and no co-author trailer.

The server does not expose arbitrary shell execution, `sudo`, `nixos-rebuild switch`, hardware scanning, or any other privileged activation path. System activation remains an explicit user-run operation outside the MCP.

Use `read_authority_contract` to inspect the repository's current agent/user boundary and `validate_declarative_contract` to check that the Nix ACL, Hermes, rebuild, and MCP safety conventions remain intact. These tools inspect repository source only; they do not inspect live `/run` state, credentials, user homes, or the vault.

The declarative ACL contract requires dedicated groups, separate read-only audit groups, compatible tmpfiles modes, and one locked `home-acl-reconcile.service` with one persistent timer. The `feilhann-home-admin` group contains only `yashindo` and grants full operating-system access to `/home/feilhann`; the existing Feilhann-to-Yashindo audit and Git policies remain intentional narrow exceptions. `rb` and the background timer use the same reconciler. Activation, reboot, sudo, and live ACL verification remain user-owned operations.

## Security boundary

All paths must remain inside the repository. Symlink paths, `.git`, `secrets/`, `.env*`, private keys, and certificate files are denied. Temporary workspaces also exclude denied paths. Mutations fail when a prepared file changed or when unrelated dirty files would be affected.

Protected Hermes state and vault plans are not MCP mutation targets, even though the operating-system ACL grants Yashindo access to Feilhann's home. The Hermes working-plan directory and the shared vault are separate authority domains; MCP does not infer live permissions from evaluated or built Nix output.

## Main workflow

```text
inspect → prepare → review diff and approval hash → apply → validate → prepare commits → approve commits
```

Run the tests with:

```sh
bun test mcp
```

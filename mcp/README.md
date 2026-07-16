# Project MCP

This repository includes a local, project-scoped MCP server for safe NixOS configuration work.

## Start it

The tracked `.codex/config.toml` entry starts the server through Bun when Codex opens this repository. For a direct local check:

```sh
bun mcp/src/server.ts
```

The server communicates through stdio and does not listen on a network port.

## Authority model

- Read tools inspect the repository, Nix flake, and Git state.
- Prepare tools work in a temporary copy and return an operation ID, approval hash, exact file hashes, and a diff. They do not modify the real checkout.
- Apply tools require the returned operation ID and approval hash. They re-check every original file hash before writing.
- Git commits require a separate commit request, one file per commit, sentence-style messages ending in a period, and no co-author trailer.

The server does not expose arbitrary shell execution, `sudo`, `nixos-rebuild switch`, hardware scanning, or any other privileged activation path. System activation remains an explicit user-run operation outside the MCP.

## Security boundary

All paths must remain inside the repository. Symlink paths, `.git`, `secrets/`, `.env*`, private keys, and certificate files are denied. Temporary workspaces also exclude denied paths. Mutations fail when a prepared file changed or when unrelated dirty files would be affected.

## Main workflow

```text
inspect → prepare → review diff and approval hash → apply → validate → prepare commits → approve commits
```

Run the tests with:

```sh
bun test mcp
```

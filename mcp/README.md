# Project MCP

This repository includes a local, project-scoped MCP server for safe NixOS
configuration work.

## Start it

The tracked `.codex/config.toml` entry starts the server through Bun when Codex
opens this repository. For a direct local check:

```sh
bun mcp/src/server.ts
```

The server communicates through stdio and does not listen on a network port.

Graphify is a separate read-only discovery MCP. Its Python environment is
managed by Pipenv from `Pipfile.lock`; it does not grant Graphify patch,
validation, or commit authority. Rebuild the graph and add the repository-local
static Nix relationships with:

```sh
./scripts/rebuild_graphify.sh
```

Then query it with `pipenv run graphify query "your question"`. Nix evaluation
remains authoritative; run `nix flake check` separately to validate the
configuration.

## Tool catalog

| Tool | Purpose | Authority |
| --- | --- | --- |
| `read_project_overview` | List repository files and Nix entry points | Read-only |
| `read_authority_contract` | Return MCP, declarative, and protected-path rules | Read-only |
| `validate_declarative_contract` | Check source-level declarative and MCP conventions | Read-only |
| `read_project_file` | Read one non-sensitive repository file | Read-only |
| `find_nix_references` | Search Nix files with `rg` | Read-only |
| `get_git_status` | Return non-sensitive branch and worktree status | Read-only |
| `inspect_flake` | Run `nix flake show --json` | Read-only |
| `audit_documentation` | Check Markdown paths, stale claims, and MCP documentation coverage | Read-only |
| `validate_mcp` | Run the fixed `bun test mcp` suite | Verification only |
| `validate_repository` | Run documentation, MCP, and read-only flake checks | Verification only |
| `prepare_patch` | Prepare exact file contents and return hashes/diff | Prepare only |
| `prepare_format` | Format Nix files in an isolated workspace and return a diff | Prepare only |
| `prepare_flake_lock_update` | Update `flake.lock` in an isolated workspace and return a diff | Prepare only |
| `prepare_working_tree_commit` | Snapshot all visible dirty paths and return a reviewable diff | Prepare only |
| `validate_flake` | Validate the checkout or a prepared operation without applying it | Read-only |
| `apply_approved_patch` | Apply an exact prepared operation after hash approval | Approval required |
| `prepare_commits` | Prepare commit messages for an already-applied operation | Approval workflow |
| `git_commit_files` | Create approved one-file commits and reject unrelated dirty paths | Approval required |
| `git_commit_working_tree` | Commit the exact reviewed working-tree snapshot, one commit per file | Approval required |

Prepare tools return an operation ID, approval hash, file hashes, and a diff.
`prepare_patch` compares against the current checkout directly; formatting and
lock updates use temporary isolated workspaces. Applying a patch requires the
exact operation ID and approval hash, and rechecks targeted files before writing.
Prepared operations retain bounded file content only: at most 128 paths and 8
MiB of stored content per operation. The server keeps at most 16 operations of
each kind, expires stale operations after 30 minutes, and removes an operation
after its approved commit completes. A rejected or partial operation remains
available for retry until it expires.

The commit tools operate after a prepared operation has been applied, except for
`prepare_working_tree_commit` and `git_commit_working_tree`. The latter pair is
specifically for externally-created dirty changes: preparation returns the full
visible diff and a snapshot hash, and commit rechecks that exact snapshot, then
creates one commit per reviewed file from the approved `commits` list (each file
with its own message). All reviewed paths must be represented, and no other path
may be committed. The working-tree path rechecks the complete snapshot before
staging, including the reviewed path set, and stages unstaged deletions explicitly.
The applied-operation path validates all paths, messages, and coverage before its
first staging mutation; protected unrelated paths are rejected rather than hidden.
Both paths remain sequential and non-atomic: a later commit failure can leave
earlier one-file commits applied, and the result reports that partial state. The
existing commit tools require one commit per file and reject unrelated dirty
paths. No tool pushes, merges, deploys, or activates NixOS.

## Authority model

- Read tools inspect the repository, Nix flake, and Git state.
- Prepare tools do not modify the real checkout.
- Apply tools require the returned operation ID and approval hash.
- Git commits require a separate approved request, one commit per file (whether
  via the prepared operations or the dedicated reviewed working-tree path);
  sentence-style subjects ending in a period, with optional valid co-author trailers.
- System activation, reboot, sudo, and live systemd/container verification are
  user-owned operations outside the MCP.

The server does not expose arbitrary shell execution, `sudo`,
`nixos-rebuild switch`, hardware scanning, Docker control, or live credential
access. `validate_mcp` and `validate_repository` use fixed commands and do not
accept command arguments.

Use `read_authority_contract` to inspect the current boundary and
`validate_declarative_contract` to check source-level declarative and MCP safety
conventions. These tools do
not inspect live `/run`, credentials, user homes, or the vault.

## Security boundary

All repository paths remain inside the configured repository root. Symlink
paths, `.git`, `.env*`, private keys, certificate files, and Git
pathspec-magic filenames whose normalized path begins with `:` are denied by
every tool. `secrets/` is denied by all tools except the reviewed
`prepare_working_tree_commit` and `git_commit_working_tree` path, which may
include secret changes only after an explicit reviewed snapshot. Temporary
workspaces also exclude denied paths. Prepared operations fail
when a targeted file changes; commit operations additionally reject unrelated
dirty paths.

Protected user state and vault plans remain outside MCP mutation targets. The
shared vault and runtime credentials are separate authority domains; MCP does
not infer live permissions from evaluated or built Nix output.

## Checks

Run the MCP tests with:

```sh
bun run mcp:test
```

Run the repository's fixed validation checks through the MCP tool or with the
repository-native commands:

```sh
nix flake check --no-build --show-trace
bun test mcp
pipenv run python -m unittest discover -s tests
```

Regenerate Graphify separately when source or vault relationships need to be
refreshed; this is maintenance, not a substitute for validation:

```sh
pipenv run graphify update .
```

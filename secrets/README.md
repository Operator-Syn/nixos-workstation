# Secrets

This directory contains encrypted SOPS files only. Do not commit plaintext
tokens, passwords, private keys, or recipient credentials here.

## GitHub credentials

`secrets/gh.yaml` contains two encrypted token keys consumed by the Hiraeth
configuration:

| Key | Consumer | Container wrapper |
| --- | --- | --- |
| `token` | Feilhann's GitHub token | `gh-feilhann` |
| `operator_syn_token` | Operator-Syn's GitHub token | `gh-operator-syn` |

NixOS materializes these as protected runtime secrets and mounts the individual
files read-only into the Hermes container. Do not decrypt, print, copy, or read
the token files directly. Use the account-specific wrappers for GitHub
operations and verify identity with `gh ... api user --jq .login`.

## Optional SSH secret

If `secrets/ssh.yaml` exists, the Home Manager SSH module decrypts its `data`
key to `~/.ssh/id_ed25519`. Create or update it using the repository root
`.sops.yaml` Age recipient and keep the private key encrypted at all times.
The SSH integration is optional; the current host's required GitHub secrets are
in `gh.yaml`.

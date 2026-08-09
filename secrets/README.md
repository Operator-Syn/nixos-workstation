# Secrets

This directory contains encrypted SOPS files only. Do not commit plaintext
tokens, passwords, private keys, or recipient credentials here.

The former service-specific GitHub secret declarations have been removed from
the active host configuration. Keep encrypted files encrypted and do not
decrypt, print, copy, or read unused token files directly.

## Optional SSH secret

If `secrets/ssh.yaml` exists, the Home Manager SSH module decrypts its `data`
key to `~/.ssh/id_ed25519`. Create or update it using the repository root
`.sops.yaml` Age recipient and keep the private key encrypted at all times.
The SSH integration is optional.

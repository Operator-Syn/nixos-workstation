# Secrets

This directory is for encrypted SOPS files only. Do not commit plaintext private
keys here.

Use the repository's root `.sops.yaml` configuration with an Age recipient,
then encrypt the SSH private key into `secrets/ssh.yaml` with a
`ssh_id_ed25519` key. Do not commit plaintext private keys or recipient
credentials.

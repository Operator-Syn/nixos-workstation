# Secrets

This directory is for encrypted SOPS files only. Do not commit plaintext private
keys here.

After creating an Age recipient, copy `.sops.yaml.example` to `.sops.yaml`,
replace `AGE_PUBLIC_KEY_HERE`, then encrypt the SSH private key into
`secrets/ssh.yaml` with a `ssh_id_ed25519` key.

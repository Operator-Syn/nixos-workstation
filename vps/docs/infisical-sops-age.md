---
status: verified
last_verified: 2026-09-09
scope: node1 live deployment and its public-safe operating procedure
public: true
related:
  - ../../secrets/README.md
---

# Infisical with SOPS and age on `node1`

This runbook documents the small single-host Infisical deployment under
`~/docker-compose/vaultwarden` on `node1`. The deployment uses Docker Compose,
an age private key for SOPS decryption, and an encrypted dotenv file. The
private key and encrypted environment file live on the VPS; neither belongs in
this public repository.

## Current layout

The following paths and behaviors were observed on `node1` on 2026-09-09:

| Item | Location or behavior |
| --- | --- |
| Compose project | `~/docker-compose/vaultwarden` |
| Compose definition | `compose.yaml` |
| SOPS binary | `~/.local/bin/sops` (validated as v3.13.3) |
| age private key | `~/.config/infisical/age.key`, mode `0600` |
| encrypted dotenv | `~/.config/infisical/infisical.env`, mode `0600` |
| backend | `infisical/infisical:v0.165.8` |
| data services | PostgreSQL 14 and Redis 7.4 on the private Compose network |
| backend exposure | loopback and the current node1 NetBird IPv4, through port 8080 |
| HTTPS entrypoint | Nginx at `infisical.yashindo.syn-forge.com` |

The exact NetBird IPv4/IPv6 addresses are intentionally omitted from this
public note. Obtain them at runtime with `netbird status --json` or
`ip -brief addr show wt0`; do not copy generated addresses or credentials into
the repository.

## Trust boundaries

1. **SOPS/age at rest.** `infisical.env` is encrypted. The age private key is
   readable only by the deployment owner (or a deliberately privileged backup
   procedure).
2. **Compose runtime.** `sops exec-env` decrypts into the child process
   environment; it does not create a plaintext `env_file`.
3. **Container network.** PostgreSQL and Redis remain on the internal network.
   The backend is also attached to a separate ordinary bridge network so
   Docker can publish its HTTP port.
4. **Nginx boundary.** Nginx terminates TLS and restricts the hostname to the
   NetBird IPv4/IPv6 ranges. Direct port 8080 access is an HTTP operational
   path, not a replacement for the HTTPS ACL.
5. **Infisical bootstrap.** The first account registration becomes the
   instance administrator. Complete that step only through the approved VPN
   hostname and then configure additional access deliberately.

## Initial or replacement setup

Run these steps on `node1` as the deployment user. They are preparatory until
the Compose start and Nginx reload are explicitly approved.

### 1. Install SOPS without placing it in the public checkout

Use the official release artifact for the host architecture, verify its
published checksum, and install it in a user-owned path if root installation is
not available:

```sh
mkdir -p "$HOME/.local/bin"
# Download the matching official sops binary and checksums into a private temp directory.
# Verify with: sha256sum -c sops-<version>.checksums.txt --ignore-missing
install -m 0755 sops-<version>.linux.amd64 "$HOME/.local/bin/sops"
"$HOME/.local/bin/sops" --version
```

The current deployment was validated with SOPS v3.13.3. Re-check the
[official SOPS releases](https://github.com/getsops/sops/releases) before
upgrading; do not paste release credentials or downloaded artifacts into this
repository.

### 2. Create or verify the age key

```sh
install -d -m 700 "$HOME/.config/infisical"
if [ ! -f "$HOME/.config/infisical/age.key" ]; then
  age-keygen -o "$HOME/.config/infisical/age.key"
  chmod 600 "$HOME/.config/infisical/age.key"
fi
age-keygen -y "$HOME/.config/infisical/age.key" >/dev/null
```

The public recipient may be recorded in a private inventory or deployment
system. Do not commit the private key or print it into logs.

### 3. Create and encrypt the dotenv

Create plaintext only in a mode-`0600` temporary file. Replace the placeholder
values locally; never put the resulting file in Git or in a backup directory
that is not access-controlled.

```sh
set -eu
umask 077
compose_dir="$HOME/docker-compose/vaultwarden"
state_dir="$HOME/.config/infisical"
plain="$(mktemp --suffix=.env)"
encrypted="$(mktemp --suffix=.env)"
trap 'rm -f "$plain" "$encrypted"' EXIT

encryption_key="$(openssl rand -hex 16)"
auth_secret="$(openssl rand -hex 32)"
postgres_password="$(openssl rand -hex 24)"

cat >"$plain" <<EOF
ENCRYPTION_KEY=$encryption_key
AUTH_SECRET=$auth_secret
POSTGRES_USER=infisical
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=infisical
DB_CONNECTION_URI=postgresql://infisical:$postgres_password@db:5432/infisical
REDIS_URL=redis://redis:6379
SITE_URL=https://infisical.yashindo.syn-forge.com
SMTP_HOST=
SMTP_PORT=
SMTP_FROM_ADDRESS=
SMTP_FROM_NAME=
SMTP_USERNAME=
SMTP_PASSWORD=
OTEL_TELEMETRY_COLLECTION_ENABLED=false
EOF

age_public="$(age-keygen -y "$state_dir/age.key")"
"$HOME/.local/bin/sops" \
  --input-type dotenv --output-type dotenv \
  --encrypt --age "$age_public" "$plain" >"$encrypted"
install -m 600 "$encrypted" "$state_dir/infisical.env"
```

The explicit dotenv flags are required when the temporary filename does not
have a dotenv extension. Without them, SOPS can encrypt the entire file as one
JSON `data` value, which `exec-env` cannot use as individual environment
variables.

### 4. Validate without printing values

```sh
cd "$HOME/docker-compose/vaultwarden"
age_key="$HOME/.config/infisical/age.key"
env_file="$HOME/.config/infisical/infisical.env"

SOPS_AGE_KEY_FILE="$age_key" \
  "$HOME/.local/bin/sops" exec-env "$env_file" \
  "docker compose config --quiet"
```

`exec-env` takes the complete child command as one shell-string argument on
the validated SOPS version. Do not run `sops -d` into a persistent file or
include `env` output in logs.

### 5. Start and verify the Compose stack

These commands change live VPS state and should be run only after review:

```sh
SOPS_AGE_KEY_FILE="$age_key" \
  "$HOME/.local/bin/sops" exec-env "$env_file" \
  "docker compose pull"
SOPS_AGE_KEY_FILE="$age_key" \
  "$HOME/.local/bin/sops" exec-env "$env_file" \
  "docker compose up -d"
SOPS_AGE_KEY_FILE="$age_key" \
  "$HOME/.local/bin/sops" exec-env "$env_file" \
  "docker compose ps"
```

The backend health endpoint is:

```sh
curl -fsS http://127.0.0.1:8080/api/status
```

The repository's deployment also binds the backend to the current NetBird
IPv4 for VPN diagnostics. Keep the value scoped to the active peer address;
update the Compose mapping if the peer is re-registered with a different
address. Do not replace the specific VPN binding with `0.0.0.0` merely to make
the service reachable.

## Nginx and VPN DNS

The Nginx file is kept with the Compose project and installed as a root-owned
file under `/etc/nginx/conf.d/`. Its certificate references use the existing
wildcard pair:

```text
/etc/letsencrypt/live/wildcard-yashindo-syn-forge/fullchain.pem
/etc/letsencrypt/live/wildcard-yashindo-syn-forge/privkey.pem
```

The site allows the NetBird IPv4 range and NetBird IPv6 prefix, then proxies to
`127.0.0.1:8080`. Install and reload only from an interactive privileged
session:

```sh
sudo install -o root -g root -m 0644 \
  "$HOME/docker-compose/vaultwarden/infisical-yashindo-syn-forge-com.conf" \
  /etc/nginx/conf.d/infisical-yashindo-syn-forge-com.conf
sudo nginx -t
sudo systemctl reload nginx
```

For the hostname to use the VPN path, create a NetBird Custom DNS Zone for
`yashindo.syn-forge.com`, distribute it to the intended peer group, and add
either:

- an A record `infisical` pointing to node1's current NetBird IPv4 **and** an
  AAAA record pointing to its current NetBird IPv6; or
- one CNAME `infisical` pointing to
  `node1.internal.netbird-network`, which already has both peer addresses.

NetBird Custom Zones support A, AAAA, and CNAME records. A CNAME cannot coexist
with A/AAAA records for the same hostname, so choose one arrangement rather
than mixing them. Verify from an enrolled peer:

```sh
getent ahostsv4 infisical.yashindo.syn-forge.com
getent ahostsv6 infisical.yashindo.syn-forge.com
curl -kfsS https://infisical.yashindo.syn-forge.com/api/status
```

If DNS resolves the public VPS address instead, Nginx correctly returns the
internal-service blocked page. If DNS resolves the VPN address but HTTPS is
`502`, check the root-owned Nginx site, its certificate paths, and the local
backend health endpoint.

## Backups and rotation

Back up the database, encrypted environment file, and age key together. A
backup is sensitive even when the environment file remains encrypted because
the age key and Infisical database jointly protect the deployment.

- Keep backups outside this public repository with restrictive ownership and
  mode.
- Never decrypt the environment into a repository path or a normal temporary
  directory with permissive mode.
- Rotate the Infisical encryption/auth/database credentials only with a tested
  database backup and a planned restart.
- After a restore, validate the SOPS decrypt, Compose config, container health,
  Nginx path, and VPN DNS separately.

## Evidence and limitations

- **Verified live:** `node1` SSH access, SOPS/age decryption, Compose config,
  healthy backend/DB/Redis containers, Nginx TLS response, and VPN A/AAAA
  access were checked on 2026-09-09.
- **User-owned:** sudo password entry, future Nginx reloads, NetBird Dashboard
  DNS changes, Infisical administrator registration, credential rotation, and
  backups.
- **Not claimed here:** production secret migration for other Compose apps,
  Infisical machine identities, SMTP delivery, or external deployment uptime.

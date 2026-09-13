#!/usr/bin/env bash
set -euo pipefail

# Public-safe operator helper. The encrypted environment is decrypted only in
# the sops child process; it is never written to the backup directory.
project_dir="${WEB_RESEARCH_PROJECT_DIR:-/home/yashindo/docker-compose/web-research}"
backup_dir="${WEB_RESEARCH_BACKUP_DIR:-/home/yashindo/backups/web-research}"
sops_bin="${SOPS_BIN:-/home/yashindo/.local/bin/sops}"
age_key_file="${SOPS_AGE_KEY_FILE:-/home/yashindo/.config/infisical/age.key}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

test -r "$project_dir/.env.sops.env"
test -x "$sops_bin"
test -r "$age_key_file"
umask 077
install -d -m 700 "$backup_dir"

SOPS_AGE_KEY_FILE="$age_key_file" "$sops_bin" exec-env "$project_dir/.env.sops.env" \
  "docker exec -e FIRECRAWL_POSTGRES_USER -e FIRECRAWL_POSTGRES_DB web-research-firecrawl-postgres sh -c 'pg_dump -U \"\$FIRECRAWL_POSTGRES_USER\" -d \"\$FIRECRAWL_POSTGRES_DB\"'" \
  >"$backup_dir/firecrawl-postgres-$stamp.sql"

docker exec web-research-firecrawl-rabbitmq rabbitmqctl export_definitions - --format json \
  >"$backup_dir/rabbitmq-definitions-$stamp.json"

# Redis data is persisted by the named volume; capture a point-in-time RDB
# through redis-cli without exposing credentials or publishing a port.
redis_tmp="/data/web-research-backup-$stamp.rdb"
docker exec web-research-firecrawl-redis redis-cli --rdb "$redis_tmp" >/dev/null
docker cp "web-research-firecrawl-redis:$redis_tmp" "$backup_dir/firecrawl-redis-$stamp.rdb"
docker exec web-research-firecrawl-redis sh -c "rm -f '$redis_tmp'"

find "$backup_dir" -type f -name 'firecrawl-*-*' -mtime +14 -delete
printf 'web-research backup written to %s\n' "$backup_dir"

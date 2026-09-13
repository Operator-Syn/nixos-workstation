#!/usr/bin/env bash
set -u

min_free_gib="${WEB_RESEARCH_MIN_FREE_GIB:-2}"
min_free_kib=$((min_free_gib * 1024 * 1024))
status=0
available_kib="$(df --output=avail / | tail -n 1 | tr -d ' ')"
if [ "${available_kib:-0}" -lt "$min_free_kib" ]; then
  logger -t web-research-monitor -p daemon.warning "root filesystem below ${min_free_gib} GiB free"
  status=1
fi

for container in web-research-firecrawl-api web-research-firecrawl-playwright web-research-firecrawl-mcp web-research-searxng; do
  state="$(docker inspect --format '{{.State.OOMKilled}} {{.RestartCount}}' "$container" 2>/dev/null || printf 'missing 0')"
  oom="${state%% *}"
  restarts="${state##* }"
  if [ "$oom" = true ] || [ "${restarts:-0}" -gt 0 ]; then
    logger -t web-research-monitor -p daemon.warning "${container} OOM=${oom} restart_count=${restarts}"
    status=1
  fi
done
exit "$status"

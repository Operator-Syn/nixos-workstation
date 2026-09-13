#!/usr/bin/env bash
set -euo pipefail

src="$(cd -- "$(dirname -- "$0")" && pwd)/nginx-web-research.conf"
dst=/etc/nginx/conf.d/web-research.conf

sudo install -o root -g root -m 0644 "$src" "$dst"
sudo nginx -t
sudo systemctl reload nginx
echo "Installed $dst and reloaded nginx."

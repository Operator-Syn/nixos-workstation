#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# graphify extract can reuse the existing manifest even during a full
# extraction. The output is ignored/generated, so remove only that directory
# to guarantee stale pre-#1504 node IDs cannot survive the rebuild.
rm -rf graphify-out
pipenv run graphify extract . --no-cluster
pipenv run python scripts/graphify_nix.py
pipenv run graphify export html

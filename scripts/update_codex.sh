#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update_codex.sh [--check]

Resolve the latest stable OpenAI Codex CLI archive and update the Nix source
version and hash. With --check, resolve and report the release without editing.
EOF
}

check_only=false
case "${1:-}" in
  "") ;;
  --check) check_only=true ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
package_file="$repo_root/home/yashindo/packages.nix"
metadata_url="https://registry.npmjs.org/%40openai%2Fcodex"

for command_name in awk chmod cmp curl git mktemp nix sed; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  fi
done

metadata="$(curl --fail --silent --show-error --location "$metadata_url")"
latest_version="$(printf '%s' "$metadata" | sed -n 's/.*"dist-tags"[[:space:]]*:[[:space:]]*{[^}]*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [[ ! "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Could not resolve a stable Codex release from npm metadata.\n' >&2
  exit 1
fi

asset_url="https://registry.npmjs.org/@openai/codex/-/codex-${latest_version}-linux-x64.tgz"
prefetch_json="$(nix store prefetch-file --json --hash-type sha256 "$asset_url")"
latest_hash="$(printf '%s' "$prefetch_json" | sed -n 's/.*"hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [[ ! "$latest_hash" =~ ^sha256- ]]; then
  printf 'Could not resolve a Nix SRI hash for %s.\n' "$asset_url" >&2
  exit 1
fi

printf 'Latest stable Codex: %s\n' "$latest_version"
printf 'Archive: %s\n' "$asset_url"
printf 'Nix hash: %s\n' "$latest_hash"

if "$check_only"; then
  printf 'No files changed (--check).\n'
  exit 0
fi

if [[ -n "$(git -C "$repo_root" status --porcelain -- "$package_file")" ]]; then
  printf 'Refusing to edit already-dirty file: %s\n' "$package_file" >&2
  printf 'Review or clear that change before running update-codex.\n' >&2
  exit 1
fi

updated_file="$(mktemp)"
trap 'rm -f -- "$updated_file"' EXIT

if ! awk \
  -v target_version="$latest_version" \
  -v target_hash="$latest_hash" \
  '
  BEGIN {
    in_codex = 0
    brace_depth = 0
    version_updates = 0
    hash_updates = 0
  }

  !in_codex && /codex-bin = pkgs\.stdenv\.mkDerivation rec/ {
    in_codex = 1
  }

  {
    if (in_codex && !version_updates && $0 ~ /^[[:space:]]*version = "/) {
      sub(/"[^"]*";[[:space:]]*$/, "\"" target_version "\";", $0)
      version_updates++
    }

    if (in_codex && !hash_updates && $0 ~ /^[[:space:]]*hash = "/) {
      sub(/"[^"]*";[[:space:]]*$/, "\"" target_hash "\";", $0)
      hash_updates++
    }

    print

    if (in_codex) {
      braces = $0
      gsub(/[^{}]/, "", braces)
      opens = braces
      gsub(/[^\{]/, "", opens)
      closes = braces
      gsub(/[^\}]/, "", closes)
      brace_depth += length(opens) - length(closes)
      if (brace_depth == 0 && version_updates && hash_updates) {
        in_codex = 0
      }
    }
  }

  END {
    if (version_updates != 1 || hash_updates != 1) {
      exit 42
    }
  }
  ' "$package_file" > "$updated_file"; then
  printf 'Could not update the Codex derivation safely.\n' >&2
  exit 1
fi

chmod --reference="$package_file" "$updated_file"

if cmp --silent "$package_file" "$updated_file"; then
  printf 'Codex is already at the latest resolved release.\n'
  exit 0
fi

mv -- "$updated_file" "$package_file"
trap - EXIT
printf 'Updated %s. Review the diff, then run rebuild to activate it.\n' "$package_file"

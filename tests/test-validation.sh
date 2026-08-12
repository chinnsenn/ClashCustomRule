#!/usr/bin/env bash
# Ensures the public validation command rejects a template/provider format mismatch.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

cp -R "$root" "$workspace/repo"
template="$workspace/repo/config/clash-meta.yaml"
perl -0pi -e 's/(  ibkr:\n    type: http\n    behavior: )classical/${1}domain/' "$template"

if (cd "$workspace/repo" && ./scripts/validate-config.sh) >"$workspace/validation.log" 2>&1; then
  printf 'validation unexpectedly accepted an IBKR provider with domain behavior\n' >&2
  sed -n '1,120p' "$workspace/validation.log" >&2
  exit 1
fi

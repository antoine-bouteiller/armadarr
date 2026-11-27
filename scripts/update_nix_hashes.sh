#!/usr/bin/env bash
# Rewrites the fixed-output hashes in flake.nix after app/frontend/pnpm-lock.yaml or go.sum changes.
set -euo pipefail
cd "$(dirname "$0")/.."

for attr in web.pnpmDeps armadarr.goModules; do
  current=$(nix eval --raw ".#$attr.outputHash")
  if output=$(nix build ".#$attr" --no-link 2>&1); then
    continue
  fi
  wanted=$(sed -n 's/^ *got: *//p' <<<"$output")
  if [ -z "$wanted" ]; then
    printf '%s\n' "$output" >&2
    exit 1
  fi
  sed -i.bak "s#$current#$wanted#" flake.nix
  rm flake.nix.bak
  echo "$attr: $wanted"
done

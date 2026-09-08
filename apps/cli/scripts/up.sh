#!/usr/bin/env bash
# Starts the named app(s), each its own independent Podman Compose
# project reachable directly on its own published host port(s) - no
# shared network or reverse proxy involved.
# Usage:
#   make up ARGS="llm-survival offline-maps"
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <app-id> [app-id...]" >&2
  echo "  (see docs/ADDING_AN_APP.md or \`make install\` for the interactive wizard)" >&2
  exit 1
fi

for app in "$@"; do
  dir="apps/$app"
  if [ ! -f "$dir/docker-compose.yml" ]; then
    echo "warn: apps/$app/docker-compose.yml not found, skipping" >&2
    continue
  fi
  echo "Starting app: $app"
  if [ ! -f "$dir/.env" ] && [ -f "$dir/.env.example" ]; then
    cp "$dir/.env.example" "$dir/.env"
  fi
  podman-compose -f "$dir/docker-compose.yml" up -d
done

echo "Done. See each app's README for its port(s), or check its docker-compose.yml."

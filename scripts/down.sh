#!/usr/bin/env bash
# Stops the named app(s).
# Usage:
#   ./scripts/down.sh llm-survival offline-maps
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <app-id> [app-id...]" >&2
  exit 1
fi

for app in "$@"; do
  dir="apps/$app"
  if [ -f "$dir/docker-compose.yml" ]; then
    echo "Stopping app: $app"
    podman-compose -f "$dir/docker-compose.yml" down
  fi
done

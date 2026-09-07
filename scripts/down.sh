#!/usr/bin/env bash
# Stops the core proxy stack and, optionally, the named apps.
# Usage:
#   ./scripts/down.sh
#   ./scripts/down.sh llm-survival offline-maps
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for app in "$@"; do
  dir="apps/$app"
  if [ -f "$dir/docker-compose.yml" ]; then
    echo "Stopping app: $app"
    podman-compose -f "$dir/docker-compose.yml" down
  fi
done

echo "Stopping core proxy..."
podman-compose down

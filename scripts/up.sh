#!/usr/bin/env bash
# Creates the shared network (if missing) and starts the core proxy stack.
# Usage:
#   ./scripts/up.sh              # proxy only
#   ./scripts/up.sh llm-survival offline-maps   # proxy + selected apps
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! podman network exists catasophie 2>/dev/null; then
  echo "Creating podman network 'catasophie'..."
  podman network create catasophie
fi

if [ ! -f .env ]; then
  echo "No .env found, copying .env.example -> .env"
  cp .env.example .env
fi

echo "Starting core proxy..."
podman-compose up -d

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

echo "Done. Visit http://${CATASOPHIE_HOSTNAME:-catasophie.local}/ (or http://<device-ip>/)"

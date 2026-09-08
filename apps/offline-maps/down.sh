#!/usr/bin/env bash
# Stops offline-maps.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping offline-maps..."
podman-compose -f "${APP_DIR}/docker-compose.yml" down

#!/usr/bin/env bash
# Stops __APP_ID__.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping __APP_ID__..."
podman-compose -f "${APP_DIR}/docker-compose.yml" down

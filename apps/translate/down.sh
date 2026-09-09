#!/usr/bin/env bash
# Stops translate.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping translate..."
podman-compose -f "${APP_DIR}/docker-compose.yml" down

#!/usr/bin/env bash
# Stops wikimed.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping wikimed..."
podman-compose -f "${APP_DIR}/docker-compose.yml" down

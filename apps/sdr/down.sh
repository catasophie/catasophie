#!/usr/bin/env bash
# Stops sdr.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping sdr..."
podman-compose -f "${APP_DIR}/docker-compose.yml" down

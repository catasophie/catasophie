#!/usr/bin/env bash
# Stops llm-assistant.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Stopping llm-assistant..."
podman-compose -f "${APP_DIR}/docker-compose.yml" down

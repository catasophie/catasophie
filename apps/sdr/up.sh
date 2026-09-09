#!/usr/bin/env bash
# Starts sdr. Idempotent - safe to re-run. Copies .env.example ->
# .env on first run if missing.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

ensure_env_file "$APP_DIR"

echo "Starting sdr..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

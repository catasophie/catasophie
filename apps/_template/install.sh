#!/usr/bin/env bash
# Interactive installer for __APP_ID__. Idempotent - safe to re-run.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "${APP_DIR}/../../scripts/lib/common.sh"

echo "== __APP_ID__ install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

# Example - replace with your app's actual required configuration:
# prompt_if_unset SOME_SETTING "Describe what this is for" "default-value" "$ENV_FILE"

echo "Starting __APP_ID__..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

mark_installed __APP_ID__
echo "== __APP_ID__ installed. Visit http://catasophie.local__URL_PATH__ =="

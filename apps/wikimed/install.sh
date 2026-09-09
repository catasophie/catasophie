#!/usr/bin/env bash
# Interactive installer for wikimed (offline reference content via
# Kiwix). Idempotent - safe to re-run.
#
# Content-related config (WIKIMED_ZIMS) is entirely owned by
# scripts/download-zim.sh, which prompts for it (and for whether to run
# the heavy download) itself, so it's self-contained whether invoked
# from here or run directly. This script only prompts for what it
# itself needs to start the containers.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

echo "== wikimed install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset DATA_DIR \
  "Directory for persistent data - ZIM files (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

prompt_if_unset WIKIMED_PORT \
  "Port to publish wikimed on (http://localhost:<port>/)" \
  "3020" "$ENV_FILE"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1
mkdir -p "${data_dir}/zims"

"$BASH" "${APP_DIR}/scripts/download-zim.sh"

echo "Starting wikimed..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

mark_installed wikimed
echo "== wikimed installed. Visit http://localhost:${WIKIMED_PORT:-3020}/ =="

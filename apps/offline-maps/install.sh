#!/usr/bin/env bash
# Interactive installer for apps/offline-maps. Idempotent - safe to
# re-run (already-set config is not re-prompted).
#
# Region-related config (MAP_SOURCE, MAP_REGION, MAP_SOURCE_URL) is
# entirely owned by scripts/import-region.sh, which prompts for it (and
# for whether to run the heavy import) itself, so it's self-contained
# whether invoked from here or run directly. This script only prompts
# for what it itself needs to start the containers.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

echo "== offline-maps install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset DATA_DIR \
  "Directory for persistent data - tiles (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

prompt_if_unset MAPS_WEB_PORT "Port to publish the map frontend on" "3010" "$ENV_FILE"
prompt_if_unset MAPS_TILES_PORT "Port to publish the tile server on" "3012" "$ENV_FILE"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1
mkdir -p "${data_dir}/tiles" "${data_dir}/raw"

"${APP_DIR}/scripts/import-region.sh"

echo "Starting tiles, web..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

mark_installed offline-maps
echo "== offline-maps installed. Visit http://localhost:${MAPS_WEB_PORT:-3010}/ =="

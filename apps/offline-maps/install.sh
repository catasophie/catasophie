#!/usr/bin/env bash
# Interactive installer for apps/offline-maps. Idempotent - safe to
# re-run (already-set config is not re-prompted; import-region.sh skips
# an extract that's already downloaded).
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "${APP_DIR}/../../scripts/lib/common.sh"

echo "== offline-maps install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset MAP_REGION \
  "Geofabrik region path, e.g. europe/germany (see https://download.geofabrik.de/)" \
  "" "$ENV_FILE"

prompt_if_unset DATA_DIR \
  "Directory for persistent data - osrm/tiles/photon (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1
mkdir -p "${data_dir}/osrm" "${data_dir}/tiles" "${data_dir}/photon" "${data_dir}/raw"

if [ -z "$(ls -A "${data_dir}/osrm" 2>/dev/null)" ]; then
  if confirm "Run the region import now? (heavy: multi-GB download + processing, can take a long time)"; then
    MAP_REGION="${MAP_REGION}" DATA_DIR="${data_dir}" "${APP_DIR}/scripts/import-region.sh"
  else
    echo "Skipping import - run MAP_REGION=${MAP_REGION} DATA_DIR=${data_dir} ./scripts/import-region.sh before this app will work."
  fi
else
  echo "Region data already present in ${data_dir}/ (skipping import)"
fi

echo "Starting osrm, tiles, geocoder, web..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

mark_installed offline-maps
echo "== offline-maps installed. Visit http://catasophie.local/maps/ =="

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

prompt_choice_if_unset MAP_SOURCE \
  "Where should the map extract come from?" \
  "geofabrik osmfr bbbike custom" "geofabrik" "$ENV_FILE"

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

case "${MAP_SOURCE:-geofabrik}" in
  bbbike)
    prompt_if_unset MAP_REGION \
      "BBBike city name, e.g. Berlin (see https://download.bbbike.org/osm/bbbike/ for the full list)" \
      "" "$ENV_FILE"
    ;;
  custom)
    prompt_if_unset MAP_REGION \
      "Region name (used to label the downloaded files - any short identifier is fine)" \
      "" "$ENV_FILE"
    prompt_if_unset MAP_SOURCE_URL \
      "Full .osm.pbf download URL" \
      "" "$ENV_FILE"
    ;;
  *)
    prompt_if_unset MAP_REGION \
      "Region path, e.g. europe/germany (see https://download.geofabrik.de/ or https://download.openstreetmap.fr/extracts/)" \
      "" "$ENV_FILE"
    ;;
esac

prompt_if_unset DATA_DIR \
  "Directory for persistent data - osrm/tiles/photon (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

prompt_if_unset MAPS_WEB_PORT "Port to publish the map frontend on" "3010" "$ENV_FILE"
prompt_if_unset MAPS_OSRM_PORT "Port to publish the routing (osrm) service on" "3011" "$ENV_FILE"
prompt_if_unset MAPS_TILES_PORT "Port to publish the tile server on" "3012" "$ENV_FILE"
prompt_if_unset MAPS_GEOCODER_PORT "Port to publish the geocoder (address search) on" "3013" "$ENV_FILE"

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1
mkdir -p "${data_dir}/osrm" "${data_dir}/tiles" "${data_dir}/photon" "${data_dir}/raw"

# Check the actual final artifacts (not just "is the dir non-empty") -
# import-region.sh builds these atomically (temp dir, moved into place
# only on success - see its own comments), so their presence reliably
# means the import genuinely completed, even if a previous attempt
# crashed partway through and left other stray files behind.
region_name=$(basename "${MAP_REGION:-}")
osrm_final="${data_dir}/osrm/region.osrm"
tiles_final="${data_dir}/tiles/${region_name}.mbtiles"
if [ -f "$osrm_final" ] && [ -f "$tiles_final" ]; then
  echo "Region already imported (${osrm_final}, ${tiles_final}) - skipping"
else
  if confirm "Run the region import now? (heavy: multi-GB download + processing, can take a long time)"; then
    MAP_REGION="${MAP_REGION}" MAP_SOURCE="${MAP_SOURCE:-geofabrik}" MAP_SOURCE_URL="${MAP_SOURCE_URL:-}" DATA_DIR="${data_dir}" "${APP_DIR}/scripts/import-region.sh"
  else
    echo "Skipping import - run MAP_REGION=${MAP_REGION} MAP_SOURCE=${MAP_SOURCE:-geofabrik} DATA_DIR=${data_dir} ./scripts/import-region.sh before this app will work."
  fi
fi

echo "Starting osrm, tiles, geocoder, web..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

mark_installed offline-maps
echo "== offline-maps installed. Visit http://localhost:${MAPS_WEB_PORT:-3010}/ =="

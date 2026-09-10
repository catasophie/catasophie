#!/usr/bin/env bash
# Imports an *additional* OSM region alongside whatever's already been
# imported (by import-region.sh and/or previous runs of this script),
# then regenerates tiles/config.json so tileserver-gl serves all of
# them side by side. Run this any time after the initial install to
# add more regions - no re-install needed.
#
# Unlike import-region.sh, this script does NOT read from or persist
# to MAP_SOURCE/MAP_REGION/MAP_SOURCE_URL in this app's .env - those
# remain whatever the *first* region was set to. Every additional
# region's source/name is only needed transiently, to know what to
# download; once its .mbtiles file exists on disk, config.json is
# regenerated from whatever .mbtiles files are actually present (see
# scripts/lib.sh's regenerate_tiles_config) - there is no separate
# list of "which regions are imported" to keep in sync.
#
# Usage (interactive):
#   ./apps/offline-maps/scripts/add-region.sh
#
# Or non-interactively:
#   ADD_REGION_SOURCE=geofabrik ADD_REGION_REGION=europe/france \
#     ./apps/offline-maps/scripts/add-region.sh
#   ADD_REGION_SOURCE=bbbike ADD_REGION_REGION=Munich \
#     ./apps/offline-maps/scripts/add-region.sh
#   ADD_REGION_SOURCE=custom ADD_REGION_REGION=my-region \
#     ADD_REGION_SOURCE_URL=https://example.com/custom.osm.pbf \
#     ./apps/offline-maps/scripts/add-region.sh
#
# Resumable, same as import-region.sh: safe to re-run/retry on failure.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"
# shellcheck source=lib.sh
source "${APP_DIR}/scripts/lib.sh"

check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

echo "== offline-maps: add a region =="

source="${ADD_REGION_SOURCE:-}"
if [ -z "$source" ]; then
  echo "Where should the map extract come from?"
  echo "  1) geofabrik (default) - https://download.geofabrik.de/"
  echo "  2) osmfr               - https://download.openstreetmap.fr/extracts/"
  echo "  3) bbbike              - https://download.bbbike.org/osm/bbbike/"
  echo "  4) custom              - provide the full .osm.pbf URL yourself"
  read -r -p "Enter number [1]: " choice
  case "${choice:-1}" in
  2) source=osmfr ;;
  3) source=bbbike ;;
  4) source=custom ;;
  *) source=geofabrik ;;
  esac
fi

region="${ADD_REGION_REGION:-}"
if [ -z "$region" ]; then
  case "$source" in
  bbbike)
    read -r -p "BBBike city name, e.g. Berlin: " region
    ;;
  custom)
    read -r -p "Region name (used to label the output files): " region
    ;;
  *)
    read -r -p "Region path, e.g. europe/france: " region
    ;;
  esac
fi
: "${region:?a region name/path is required}"

source_url="${ADD_REGION_SOURCE_URL:-}"
if [ "$source" = "custom" ] && [ -z "$source_url" ]; then
  read -r -p "Full .osm.pbf download URL: " source_url
fi
source_url="$(resolve_source_url "$source" "$region" "$source_url")"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1

id="$(region_id "$region")"
if [ -f "${data_dir}/tiles/${id}.mbtiles" ]; then
  echo "'${region}' (id: ${id}) is already imported - nothing to do."
  exit 0
fi

if import_region_tiles "$data_dir" "$id" "$region" "$source_url"; then
  regenerate_tiles_config "$data_dir" "${APP_DIR}/templates/style.json.template"
  echo
  echo "'${region}' added (id: ${id})."
  echo "Restart the tiles service to pick it up:"
  echo "  podman-compose -f ${APP_DIR}/docker-compose.yml restart tiles"
  echo "Then hard-refresh the web viewer - it re-fetches the region list on load."
fi

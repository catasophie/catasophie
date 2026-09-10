#!/usr/bin/env bash
# Downloads an OSM extract and builds an .mbtiles vector tileset (via
# Planetiler) for the *first* region, then (re)generates the
# tileserver-gl config that serves it.
#
# Routing (OSRM) and geocoding (Photon) are disabled for now to keep the
# install slim - see git history for that setup if you want to bring it
# back.
#
# This is a heavy, one-time setup step - it can take a long time and
# significant disk space depending on region size. Not run automatically
# by anything else in this repo except apps/offline-maps/install.sh
# (which just calls this script unconditionally - all region-related
# prompting/config lives here).
#
# To import *additional* regions after this one (so multiple regions
# are all served side by side), use scripts/add-region.sh instead of
# re-running this script - this one is specifically for the region
# whose MAP_SOURCE/MAP_REGION are persisted in this app's .env (used
# e.g. by install.sh to know whether the first-time import already
# happened). See scripts/add-region.sh and README.md for details.
#
# Self-contained/idempotent: prompts (and persists to this app's .env)
# for whatever required config isn't already set - MAP_SOURCE,
# MAP_REGION, and (for MAP_SOURCE=custom) MAP_SOURCE_URL - so it's safe
# to run directly, without install.sh, on a fresh checkout. Values
# already exported in the process environment take precedence over
# .env and skip their prompt too (see prompt_if_unset/
# prompt_choice_if_unset in apps/cli/scripts/lib/common.sh), so the
# non-interactive form below still works:
#
#   MAP_REGION=europe/germany MAP_SOURCE=geofabrik ./scripts/import-region.sh
#
# MAP_SOURCE selects where the extract is downloaded from:
#   geofabrik (default) - https://download.geofabrik.de/ - MAP_REGION is
#     a hierarchical region path, e.g. europe/germany
#   osmfr               - https://download.openstreetmap.fr/extracts/
#     mirror, same MAP_REGION format as geofabrik
#   bbbike              - https://download.bbbike.org/osm/bbbike/ -
#     MAP_REGION is just a city name, e.g. Berlin
#   custom              - set MAP_SOURCE_URL to the full .osm.pbf URL
#     yourself; MAP_REGION is only used to label the output files
# MAP_SOURCE_URL, if set, always overrides the computed URL regardless
# of MAP_SOURCE (useful for one-off/manual runs).
#
# DATA_DIR can be set (absolute path) to build into an external drive
# instead of the default ./data next to this app - read from this app's
# .env if already configured (e.g. by install.sh), same as everything
# else here.
#
# Resumable: the download and the tiles build each only run if their
# final output isn't already present, and the tiles build writes into a
# temporary ".building" location first, only moving into the real final
# path once it fully succeeds - so a crash/interruption partway through
# never leaves behind a partial file that looks complete. Re-run this
# script to pick up wherever it left off.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"
# shellcheck source=lib.sh
source "${APP_DIR}/scripts/lib.sh"

check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_choice_if_unset MAP_SOURCE \
  "Where should the map extract come from?" \
  "geofabrik osmfr bbbike custom" "geofabrik" "$ENV_FILE"

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

: "${MAP_REGION:?MAP_REGION is required (see prompts above, or set it in ${ENV_FILE})}"
data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1

id="$(region_id "$MAP_REGION")"
source_url="$(resolve_source_url "${MAP_SOURCE:-geofabrik}" "$MAP_REGION" "${MAP_SOURCE_URL:-}")"

if import_region_tiles "$data_dir" "$id" "$MAP_REGION" "$source_url"; then
  regenerate_tiles_config "$data_dir" "${APP_DIR}/templates/style.json.template"
  echo
  echo "Done. MAP_REGION=${MAP_REGION} is set in ${ENV_FILE}. Start the app with:"
  echo "  podman-compose -f ${APP_DIR}/docker-compose.yml up -d"
  echo
  echo "To import additional regions later, use: ${APP_DIR}/scripts/add-region.sh"
fi

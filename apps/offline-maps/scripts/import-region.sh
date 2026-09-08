#!/usr/bin/env bash
# Downloads an OSM extract and builds an .mbtiles vector tileset (via
# Planetiler) for it.
#
# Routing (OSRM) and geocoding (Photon) are disabled for now to keep the
# install slim - see git history for that setup if you want to bring it
# back.
#
# This is a heavy, one-time (or per-region-change) setup step - it can
# take a long time and significant disk space depending on region size.
# Not run automatically by anything else in this repo except
# apps/offline-maps/install.sh (which just calls this script
# unconditionally - all region-related prompting/config lives here).
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
region_name=$(basename "$MAP_REGION")
data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1

if [ -n "${MAP_SOURCE_URL:-}" ]; then
  source_url="$MAP_SOURCE_URL"
else
  case "${MAP_SOURCE:-geofabrik}" in
  osmfr)
    source_url="https://download.openstreetmap.fr/extracts/${MAP_REGION}-latest.osm.pbf"
    ;;
  bbbike)
    source_url="https://download.bbbike.org/osm/bbbike/${MAP_REGION}/${MAP_REGION}.osm.pbf"
    ;;
  *)
    source_url="https://download.geofabrik.de/${MAP_REGION}-latest.osm.pbf"
    ;;
  esac
fi

mkdir -p "${data_dir}/raw" "${data_dir}/tiles"
pbf="${data_dir}/raw/${region_name}-latest.osm.pbf"

# The actual heavy work (download + tiles build) only happens if it
# isn't already done - so re-running this script (or install.sh, which
# now always calls it unconditionally) is a fast, silent no-op once a
# region has been fully imported.
mbtiles_final="${data_dir}/tiles/${region_name}.mbtiles"
if [ -f "$mbtiles_final" ]; then
  echo "Vector tiles already built (${mbtiles_final}) - skipping"
else
  if ! confirm "Run the region import now? (heavy: multi-GB download + processing, can take a long time)"; then
    echo "Skipping import - re-run ${APP_DIR}/scripts/import-region.sh (or make install ARGS=\"offline-maps\") when ready."
    exit 0
  fi

  if [ ! -f "$pbf" ]; then
    echo "Downloading ${MAP_REGION} extract from ${source_url}..."
    curl -fL --retry 3 -o "$pbf.part" "$source_url"
    mv "$pbf.part" "$pbf"
  else
    echo "Using existing extract: $pbf"
  fi

  echo "== Building vector tiles (Planetiler) =="
  build_dir="${data_dir}/tiles/.building"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  podman run --rm \
    -v "${data_dir}/raw:/data/raw" \
    -v "${build_dir}:/data/tiles" \
    -e JAVA_TOOL_OPTIONS="-Xmx5g" \
    ghcr.io/onthegomap/planetiler:latest \
    --download --area="${region_name}" --osm-path="/data/raw/${region_name}-latest.osm.pbf" \
    --output="/data/tiles/${region_name}.mbtiles"
  mv "${build_dir}/${region_name}.mbtiles" "$mbtiles_final"
  rm -rf "$build_dir"
fi

cat >"${data_dir}/tiles/config.json" <<EOF
{
  "options": { "paths": { "root": "/data" } },
  "data": { "${region_name}": { "mbtiles": "${region_name}.mbtiles" } }
}
EOF

echo
echo "Done. MAP_REGION=${MAP_REGION} is set in ${ENV_FILE}. Start the app with:"
echo "  podman-compose -f ${APP_DIR}/docker-compose.yml up -d"

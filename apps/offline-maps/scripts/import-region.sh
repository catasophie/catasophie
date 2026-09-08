#!/usr/bin/env bash
# Downloads an OSM extract for $MAP_REGION and builds:
#   - an OSRM routing graph (car profile, MLD algorithm)
#   - an .mbtiles vector tileset (via Planetiler)
#   - a Photon geocoder index (prebuilt per-country dump when available)
#
# This is a heavy, one-time (or per-region-change) setup step - it can
# take a long time and significant disk space depending on region size.
# Not run automatically by anything else in this repo.
#
# Resumable: each stage (pbf download, osrm graph, tiles) only runs if
# its final output isn't already present, and each builds into a
# temporary ".building" location first, only moving into the real final
# path once it fully succeeds - so a crash/interruption partway through a
# stage never leaves behind a partial file that looks complete. Re-run
# this script to pick up wherever it left off.
#
# Usage: MAP_REGION=europe/germany ./scripts/import-region.sh
# DATA_DIR can be set (absolute path) to build into an external drive
# instead of the default ./data next to this app; install.sh sets this
# for you when invoking this script.
#
# MAP_SOURCE selects where the extract is downloaded from (install.sh
# prompts for this):
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
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

: "${MAP_REGION:?set MAP_REGION, e.g. europe/germany (see https://download.geofabrik.de/), or a BBBike city name if MAP_SOURCE=bbbike}"
region_name=$(basename "$MAP_REGION")
data_dir="${DATA_DIR:-$(pwd)/data}"

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

mkdir -p "${data_dir}/raw" "${data_dir}/osrm" "${data_dir}/tiles" "${data_dir}/photon"
pbf="${data_dir}/raw/${region_name}-latest.osm.pbf"

if [ ! -f "$pbf" ]; then
  echo "Downloading ${MAP_REGION} extract from ${source_url}..."
  curl -fL --retry 3 -o "$pbf.part" "$source_url"
  mv "$pbf.part" "$pbf"
else
  echo "Using existing extract: $pbf"
fi

osrm_final="${data_dir}/osrm/region.osrm"
if [ -f "$osrm_final" ]; then
  echo "OSRM graph already built (${osrm_final}) - skipping"
else
  echo "== Building OSRM graph (car profile, MLD) =="
  # Build into a scratch subdir first - osrm-extract/partition/customize
  # run in sequence against the *same* file, each augmenting it in
  # place, so a failure at any stage leaves a half-built graph. Only
  # move the whole set of region.osrm* files into their final location
  # after all three stages succeed, so "region.osrm exists in its final
  # location" reliably means the graph is actually complete and usable.
  build_dir="${data_dir}/osrm/.building"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  cp "$pbf" "${build_dir}/region.osm.pbf"
  podman run --rm -v "${build_dir}:/data" docker.io/osrm/osrm-backend:latest \
    osrm-extract -p /opt/car.lua /data/region.osm.pbf
  podman run --rm -v "${build_dir}:/data" docker.io/osrm/osrm-backend:latest \
    osrm-partition /data/region.osrm
  podman run --rm -v "${build_dir}:/data" docker.io/osrm/osrm-backend:latest \
    osrm-customize /data/region.osrm
  rm -f "${build_dir}/region.osm.pbf"
  # Move the whole region.osrm* file set (OSRM produces several sidecar
  # files sharing this prefix) into the real osrm/ dir, then the marker
  # (region.osrm) only appears once everything else is already in place.
  mv "${build_dir}"/region.osrm* "${data_dir}/osrm/"
  rmdir "$build_dir" 2>/dev/null || true
fi

mbtiles_final="${data_dir}/tiles/${region_name}.mbtiles"
if [ -f "$mbtiles_final" ]; then
  echo "Vector tiles already built (${mbtiles_final}) - skipping"
else
  echo "== Building vector tiles (Planetiler) =="
  build_dir="${data_dir}/tiles/.building"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  podman run --rm \
    -v "${data_dir}/raw:/data/raw" \
    -v "${build_dir}:/data/tiles" \
    ghcr.io/onthegomap/planetiler:latest \
    --download --area="${region_name}" --osm-path="/data/raw/${region_name}-latest.osm.pbf" \
    --output="/data/tiles/${region_name}.mbtiles"
  mv "${build_dir}/${region_name}.mbtiles" "$mbtiles_final"
  rm -rf "$build_dir"
fi
cat > "${data_dir}/tiles/config.json" <<EOF
{
  "options": { "paths": { "root": "/data" } },
  "data": { "${region_name}": { "mbtiles": "${region_name}.mbtiles" } }
}
EOF

echo "== Photon geocoder index =="
echo "Photon works best from a prebuilt per-country search index rather than"
echo "building one from scratch (which needs a Nominatim/osm2pgsql pipeline)."
echo "Check https://github.com/komoot/photon#creating-your-own-photon-database"
echo "for current download links, or build your own per that guide, and"
echo "extract the result into ${data_dir}/photon/ before starting the geocoder"
echo "service."

echo
echo "Done. Set MAP_REGION=${MAP_REGION} in .env, then:"
echo "  podman-compose -f apps/offline-maps/docker-compose.yml up -d"

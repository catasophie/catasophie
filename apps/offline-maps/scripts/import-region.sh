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
  curl -fL --retry 3 -o "$pbf" "$source_url"
else
  echo "Using existing extract: $pbf"
fi

echo "== Building OSRM graph (car profile, MLD) =="
cp "$pbf" "${data_dir}/osrm/region.osm.pbf"
podman run --rm -v "${data_dir}/osrm:/data" docker.io/osrm/osrm-backend:latest \
  osrm-extract -p /opt/car.lua /data/region.osm.pbf
podman run --rm -v "${data_dir}/osrm:/data" docker.io/osrm/osrm-backend:latest \
  osrm-partition /data/region.osrm
podman run --rm -v "${data_dir}/osrm:/data" docker.io/osrm/osrm-backend:latest \
  osrm-customize /data/region.osrm
rm -f "${data_dir}/osrm/region.osm.pbf"

echo "== Building vector tiles (Planetiler) =="
podman run --rm \
  -v "${data_dir}/raw:/data/raw" \
  -v "${data_dir}/tiles:/data/tiles" \
  ghcr.io/onthegomap/planetiler:latest \
  --download --area="${region_name}" --osm-path="/data/raw/${region_name}-latest.osm.pbf" \
  --output="/data/tiles/${region_name}.mbtiles"
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

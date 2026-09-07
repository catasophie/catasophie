#!/usr/bin/env bash
# Downloads a Geofabrik OSM extract for $MAP_REGION and builds:
#   - an OSRM routing graph (car profile, MLD algorithm)
#   - an .mbtiles vector tileset (via Planetiler)
#   - a Photon geocoder index (prebuilt per-country dump when available)
#
# This is a heavy, one-time (or per-region-change) setup step - it can
# take a long time and significant disk space depending on region size.
# Not run automatically by anything else in this repo.
#
# Usage: MAP_REGION=europe/germany ./scripts/import-region.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

: "${MAP_REGION:?set MAP_REGION, e.g. europe/germany (see https://download.geofabrik.de/)}"
region_name=$(basename "$MAP_REGION")

mkdir -p data/raw data/osrm data/tiles data/photon
pbf="data/raw/${region_name}-latest.osm.pbf"

if [ ! -f "$pbf" ]; then
  echo "Downloading ${MAP_REGION} extract from Geofabrik..."
  curl -fL --retry 3 -o "$pbf" "https://download.geofabrik.de/${MAP_REGION}-latest.osm.pbf"
else
  echo "Using existing extract: $pbf"
fi

echo "== Building OSRM graph (car profile, MLD) =="
cp "$pbf" data/osrm/region.osm.pbf
podman run --rm -v "$(pwd)/data/osrm:/data" docker.io/osrm/osrm-backend:latest \
  osrm-extract -p /opt/car.lua /data/region.osm.pbf
podman run --rm -v "$(pwd)/data/osrm:/data" docker.io/osrm/osrm-backend:latest \
  osrm-partition /data/region.osrm
podman run --rm -v "$(pwd)/data/osrm:/data" docker.io/osrm/osrm-backend:latest \
  osrm-customize /data/region.osrm
rm -f data/osrm/region.osm.pbf

echo "== Building vector tiles (Planetiler) =="
podman run --rm \
  -v "$(pwd)/data/raw:/data/raw" \
  -v "$(pwd)/data/tiles:/data/tiles" \
  ghcr.io/onthegomap/planetiler:latest \
  --download --area="${region_name}" --osm-path="/data/raw/${region_name}-latest.osm.pbf" \
  --output="/data/tiles/${region_name}.mbtiles"
cat > data/tiles/config.json <<EOF
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
echo "extract the result into ./data/photon/ before starting the geocoder"
echo "service."

echo
echo "Done. Set MAP_REGION=${MAP_REGION} in .env, then:"
echo "  podman-compose -f apps/offline-maps/docker-compose.yml up -d"

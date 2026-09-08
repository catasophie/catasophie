# offline-maps

Offline maps, address search, and basic driving-route navigation, entirely
from locally stored OpenStreetMap data - no internet required once set up.

## Components

- **osrm** - routing engine ([Project OSRM](https://project-osrm.org/))
- **tiles** - [tileserver-gl](https://github.com/maptiler/tileserver-gl)
  serving a pre-built vector tileset for the chosen region
- **geocoder** - [Photon](https://github.com/komoot/photon) address search
- **web** - a minimal static [MapLibre GL](https://maplibre.org/) page
  (search start/end, request a route, draw it)

## One-time setup: import a region

`./install.sh` prompts for the data source (`MAP_SOURCE`) and region -
choose from:

- **geofabrik** (default) - [Geofabrik](https://download.geofabrik.de/),
  `MAP_REGION` is a hierarchical region path, e.g. `europe/germany`
- **osmfr** - [openstreetmap.fr](https://download.openstreetmap.fr/extracts/)
  mirror, same `MAP_REGION` format as Geofabrik
- **bbbike** - [BBBike](https://download.bbbike.org/osm/bbbike/) per-city
  extracts, `MAP_REGION` is just a city name, e.g. `Berlin`
- **custom** - provide the full `.osm.pbf` URL yourself via
  `MAP_SOURCE_URL`; `MAP_REGION` is only used to label the output files

Or run the import script directly:

```sh
MAP_REGION=europe/germany MAP_SOURCE=geofabrik ./apps/offline-maps/scripts/import-region.sh
MAP_REGION=Berlin MAP_SOURCE=bbbike ./apps/offline-maps/scripts/import-region.sh
MAP_REGION=my-region MAP_SOURCE_URL=https://example.com/custom.osm.pbf ./apps/offline-maps/scripts/import-region.sh
```

This downloads the OSM extract and builds the OSRM graph + vector tiles
into `apps/offline-maps/data/` (gitignored, or wherever `DATA_DIR` in
`.env` points - see the root README's "Storing data on an external
drive" section). It also explains how to add a Photon geocoder index
(prebuilt per-country, see script output).

This is a heavy step - expect it to take a while and use several GB of
disk for anything larger than a small country/state.

## Run

```sh
podman-compose -f apps/offline-maps/docker-compose.yml up -d
```

Visit `http://catasophie.local/maps/`.

## Notes / known limitations of this first version

- The MapLibre style in `web/index.html` is intentionally minimal
  (background + water + roads) - swap in a full style matching your
  Planetiler layer schema for proper cartography.
- Only driving directions are wired up (OSRM `car` profile). Add
  `bicycle`/`foot` profiles by re-running `osrm-extract` with a different
  Lua profile and exposing another OSRM service/route.
- Changing region later: re-run `import-region.sh` with a new
  `MAP_REGION` (old data in `data/` is not automatically cleaned up).

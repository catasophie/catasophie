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

```sh
MAP_REGION=europe/germany ./apps/offline-maps/scripts/import-region.sh
```

See [Geofabrik](https://download.geofabrik.de/) for valid region paths.
This downloads the OSM extract and builds the OSRM graph + vector tiles
into `apps/offline-maps/data/` (gitignored). It also explains how to add a
Photon geocoder index (prebuilt per-country, see script output).

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

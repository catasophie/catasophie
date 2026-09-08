# offline-maps

Offline map viewing, entirely from locally stored OpenStreetMap data -
no internet required once set up. Routing and address search (osrm /
geocoder) are disabled for now to keep the install slimmer - see git
history if you want to bring them back.

## Components

- **tiles** - [tileserver-gl](https://github.com/maptiler/tileserver-gl)
  serving a pre-built vector tileset for the chosen region - published on
  `http://localhost:${MAPS_TILES_PORT:-3012}/`
- **web** - a minimal static [MapLibre GL](https://maplibre.org/) page
  (pans to your location) - published on
  `http://localhost:${MAPS_WEB_PORT:-3010}/`, calls the tiles service
  above directly by port (no reverse proxy in front - see
  `templates/config.js.template`)

## One-time setup: import a region

`scripts/import-region.sh` prompts for the data source (`MAP_SOURCE`)
and region if they aren't already configured, and persists your answers
to this app's `.env`. `make install ARGS="offline-maps"` calls it for you
automatically after asking the questions it needs itself (data
directory, ports) - choose from:

- **geofabrik** (default) - [Geofabrik](https://download.geofabrik.de/),
  `MAP_REGION` is a hierarchical region path, e.g. `europe/germany`
- **osmfr** - [openstreetmap.fr](https://download.openstreetmap.fr/extracts/)
  mirror, same `MAP_REGION` format as Geofabrik
- **bbbike** - [BBBike](https://download.bbbike.org/osm/bbbike/) per-city
  extracts, `MAP_REGION` is just a city name, e.g. `Berlin`
- **custom** - provide the full `.osm.pbf` URL yourself via
  `MAP_SOURCE_URL`; `MAP_REGION` is only used to label the output files

Or run the import script directly (e.g. to import ahead of time, before
running the installer, or to re-run for a different region) - either
interactively, or non-interactively by passing the answers as
environment variables (these take precedence over prompts, and get
saved to `.env` too):

```sh
MAP_REGION=europe/germany MAP_SOURCE=geofabrik ./apps/offline-maps/scripts/import-region.sh
MAP_REGION=Berlin MAP_SOURCE=bbbike ./apps/offline-maps/scripts/import-region.sh
MAP_REGION=my-region MAP_SOURCE_URL=https://example.com/custom.osm.pbf ./apps/offline-maps/scripts/import-region.sh
```

This downloads the OSM extract and builds the vector tiles into
`apps/offline-maps/data/` (gitignored, or wherever `DATA_DIR` in `.env`
points - see the root README's "Storing data on an external drive"
section).

This is a heavy step - expect it to take a while and use several GB of
disk for anything larger than a small country/state.

## Run

```sh
podman-compose -f apps/offline-maps/docker-compose.yml up -d
```

Visit `http://localhost:3010/` (or whatever you set `MAPS_WEB_PORT` to -
also reachable at `http://<device-ip>:3010/` from another device on the
LAN).

## Notes / known limitations of this version

- Routing (OSRM) and address search (Photon) are disabled for now to
  keep the install lighter/faster - only tile viewing is wired up. See
  git history (`docker-compose.yml`, `scripts/import-region.sh`,
  `web/index.html` before this change) for the previous setup if you
  want to bring them back.
- Changing region later: re-run `import-region.sh` with a new
  `MAP_REGION` (old data in `data/` is not automatically cleaned up).
- Changing the tiles port after the frontend has already loaded once:
  hard-refresh the page so it re-fetches `config.js` (it's regenerated
  from `.env` each time the `web` container starts).

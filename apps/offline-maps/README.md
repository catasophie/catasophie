# offline-maps

Offline map viewing, entirely from locally stored OpenStreetMap data -
no internet required once set up. Routing and address search (osrm /
geocoder) are disabled for now to keep the install slimmer - see git
history if you want to bring them back.

## Components

- **tiles** - [tileserver-gl](https://github.com/maptiler/tileserver-gl)
  serving a pre-built vector tileset per imported region (see "Adding
  more regions later" below) - published on
  `http://localhost:${MAPS_TILES_PORT:-3012}/`
- **web** - a minimal static [MapLibre GL](https://maplibre.org/) page
  (region picker + a "you are here" location dot/heading, via
  MapLibre's `GeolocateControl`) - published on both:
  - `https://localhost:${MAPS_WEB_TLS_PORT:-3010}/` (default/primary -
    self-signed cert - see "Location marker / HTTPS" below for why
    this exists and is needed for the location marker when accessed
    via LAN IP)
  - `http://localhost:${MAPS_WEB_PORT:-3011}/` (plain HTTP fallback -
    location marker won't work over this one unless accessed as
    localhost)

  nginx transparently reverse-proxies tileserver-gl's own paths
  (`/styles*`, `/data/*`, `/fonts/*`, `/sprites/*`, `/health`) through
  to the `tiles` service on both of the above (see
  `templates/nginx.conf`), so the frontend just uses same-origin
  relative paths - no separate host:port to know about, and no "mixed
  content" browser blocking once the page itself is HTTPS. MapLibre GL
  JS/CSS are vendored into `web/vendor/maplibre-gl/` (not loaded from a
  CDN), consistent with this app needing to work with zero internet
  access.

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

## Adding more regions later

Multiple regions can be served side by side - each imported region gets
its own vector tileset and its own style/data source in tileserver-gl,
and the web viewer shows a region picker whenever more than one has
been imported.

To add a region after the initial install, use `scripts/add-region.sh`
instead of re-running `import-region.sh` (that one is tied to the
first region's `MAP_SOURCE`/`MAP_REGION` persisted in `.env`):

```sh
./apps/offline-maps/scripts/add-region.sh
# or non-interactively:
ADD_REGION_SOURCE=geofabrik ADD_REGION_REGION=europe/france \
  ./apps/offline-maps/scripts/add-region.sh
ADD_REGION_SOURCE=bbbike ADD_REGION_REGION=Munich \
  ./apps/offline-maps/scripts/add-region.sh
ADD_REGION_SOURCE=custom ADD_REGION_REGION=my-region \
  ADD_REGION_SOURCE_URL=https://example.com/custom.osm.pbf \
  ./apps/offline-maps/scripts/add-region.sh
```

After it finishes, restart the tiles service so it picks up the new
region (no need to restart `web`), then hard-refresh the browser tab:

```sh
podman-compose -f apps/offline-maps/docker-compose.yml restart tiles
```

Each region's tiles/style/config are (re)derived entirely from the
`.mbtiles` files present under `data/tiles/` - there's no separate
"list of installed regions" to keep in sync, so re-running
`add-region.sh` for a region already imported is a fast no-op, and
deleting a region is just deleting its `<id>.mbtiles` (and matching
`<id>.name`/`styles/<id>/`) file and re-running either script once to
regenerate `config.json`.

## Run

```sh
podman-compose -f apps/offline-maps/docker-compose.yml up -d
```

Visit `https://localhost:3010/` (or whatever you set `MAPS_WEB_TLS_PORT`
to - also reachable at `https://<device-ip>:3010/` from another device
on the LAN, after clicking through the one-time self-signed cert
warning - see "Location marker / HTTPS" below). A plain-HTTP fallback
is also published at `http://localhost:3011/` (`MAPS_WEB_PORT`).

## Location marker / HTTPS

The "you are here" marker (top-right button on the map, via MapLibre's
`GeolocateControl`) uses the browser's Geolocation API, which browsers
only expose on a *secure context*: `https://` origins, or specifically
`http://localhost` (the *only* plain-HTTP exception). This is why
HTTPS (`MAPS_WEB_TLS_PORT`, default `3010`) is the default/primary port
for this app:

- Opening the map at `https://localhost:3010/` **or**
  `http://localhost:3011/` **on the device itself**: the button works
  either way (both are secure contexts for "localhost").
- Opening it from **another device on the LAN**: only
  `https://<device-ip>:3010/` works for the button -
  `http://<device-ip>:3011/` will have it silently do nothing (browser
  blocking it, not a bug). The page detects this and shows a banner
  with the right link if you land on the insecure one.

`https://<device-ip>:3010/` uses a self-signed certificate generated
locally by `scripts/ensure-tls-cert.sh` (called automatically by
`install.sh`/`up.sh` - there's no public DNS name to get a real,
CA-trusted cert for on a LAN-only device). Your browser will show a
"connection is not private" / "not trusted" warning the first time -
this is expected; click through it (usually "Advanced" → "Proceed to
`<device-ip>` (unsafe)") and it won't ask again for that device. Once
accepted, everything else works identically to the plain-HTTP port
(same map, same regions, same tiles) - only the location marker
actually needs it.

If your device's LAN IP changes later and the browser starts
complaining about a hostname mismatch instead of just "not trusted",
delete `data/certs/web.{crt,key}` (or wherever `DATA_DIR` points) and
run `./apps/offline-maps/scripts/ensure-tls-cert.sh` again, then
restart: `podman-compose -f apps/offline-maps/docker-compose.yml
restart web`.

## Using these tiles from ATAK (or other raster-tile clients)

The `tiles` service (tileserver-gl) serves each imported region both as
**vector** tiles (what the bundled `web` viewer uses) and, via the same
already-registered per-region style, as plain **raster PNG** XYZ tiles -
no extra config needed. The style id is the region's sanitized id (see
`region_id()` in `scripts/lib.sh` - e.g. `MAP_REGION=europe/germany`
becomes `germany`); list all currently-registered ids/names at
`http://<device-ip>:${MAPS_TILES_PORT:-3012}/styles.json`:

```
http://<device-ip>:${MAPS_TILES_PORT:-3012}/styles/<region-id>/{z}/{x}/{y}.png
```

In ATAK, add this as a custom tile source (menu → Settings → Tool
Preferences → Map Data Sources, or via Import Manager on some
versions, depending on ATAK version) using the URL template above with
your device's actual IP in place of `<device-ip>`. See
`apps/tak-server/README.md` if you're also running a TAK server on this
network - the two apps aren't otherwise integrated, ATAK just talks to
each directly.

## Notes / known limitations of this version

- Routing (OSRM) and address search (Photon) are disabled for now to
  keep the install lighter/faster - only tile viewing is wired up. See
  git history (`docker-compose.yml`, `scripts/import-region.sh`,
  `web/index.html` before this change) for the previous setup if you
  want to bring them back.
- Multiple regions are supported (see "Adding more regions later"
  above) - the web viewer's region picker only appears once more than
  one has been imported.
- The location marker requires HTTPS when accessed via LAN IP (browser
  security requirement, not specific to this app) - see "Location
  marker / HTTPS" above.
- Changing `MAPS_WEB_TLS_PORT` after the frontend has already loaded
  once: hard-refresh the page so it re-fetches `config.js` (it's
  regenerated from `.env` each time the `web` container starts).

# Dashboard (Resilience Hub)

A single-page dashboard that lists every other app in this repo, shows
whether it's installed/running/stopped, and lets you start or stop it
directly from the browser.

## Why this app is different from every other app in `apps/`

Every other app in this repo is a fully independent Podman Compose
project - see `docs/ARCHITECTURE.md` and `docs/ADDING_AN_APP.md`. The
dashboard is a deliberate, narrow exception to that "no
orchestrator" design: to start/stop *other* apps' containers, it needs
to run `podman-compose`/`podman` on the host, which is far simpler to do
as a plain process running directly on the host than as a container
that would otherwise need the podman socket and this whole repo
bind-mounted into it. So:

- There's no `docker-compose.yml` here - `install.sh`/`up.sh`/`down.sh`
  start/stop a plain `node server.js` process directly, tracked via a
  PID file (`.dashboard.pid`), not a container.
- It still needs `podman` and `podman-compose` on `PATH` (to inspect and
  control the other apps), plus Node.js 18+ and `npm`.
- It never runs `podman-compose` itself on another app's behalf - it
  only ever calls that app's own `up.sh`/`down.sh`, so every app's own
  idempotent install contract (env file handling, etc.) is preserved
  unchanged. The dashboard is just a friendlier way to click a button
  instead of running `./apps/<id>/up.sh` yourself.

## Run

```sh
./apps/dashboard/install.sh   # first time: prompts for the port, npm install, starts it
./apps/dashboard/up.sh        # start (idempotent)
./apps/dashboard/down.sh      # stop
```

Then visit `http://localhost:8000/` (or whatever `DASHBOARD_PORT` is set
to in `.env` - also reachable at `http://<device-ip>:8000/` from another
device on the LAN).

## Configuring which apps show up

There's no config file to edit here - the dashboard discovers apps by
scanning `apps/<id>/manifest.json` across this repo (see
`docs/ADDING_AN_APP.md` for the full schema). To add or change an app on
the dashboard, edit (or create) that app's own `manifest.json`, e.g.:

```json
{
  "name": "Offline Maps",
  "description": "One short sentence, shown on the dashboard card.",
  "category": "Navigation",
  "icon": "map",
  "port": { "envVar": "MAPS_WEB_PORT", "default": 3010 }
}
```

An app with no `manifest.json` simply doesn't appear - this is why
`apps/_template`, `apps/cli`, and the dashboard itself never show up.
The actual port is read live from that app's `.env` (via `port.envVar`),
falling back to `port.default` if `.env`/that var is missing. There's no
per-app `host` field - see "Reachable from other devices on the LAN"
below for where the host part of each app's URL comes from.

This scan only happens **at dashboard startup, or when you click
"Rescan"** (`POST /api/rescan`) - not on every page load or status poll,
since re-reading every manifest and `.env` on every request would be
wasteful for something that rarely changes. So after adding/editing a
`manifest.json` or changing a port in some app's `.env`, either restart
the dashboard (`./down.sh && ./up.sh`) or click Rescan to pick it up.

## Reachable from other devices on the LAN

Every app's URL is built as `<protocol>://<advertise-host>:<port><path>`,
where `<advertise-host>` is resolved once per scan (startup or Rescan),
not `"localhost"` - a link that says `localhost` would only ever work
from the same device the dashboard runs on, not from a phone/laptop
elsewhere on the LAN.

By default this is auto-detected: the dashboard picks the first
non-internal IPv4 address it finds via the OS's network interfaces. If
this device has more than one active interface (e.g. Ethernet and its
own WiFi hotspot both up), it logs the others it found and you can pin
one explicitly by setting `DASHBOARD_ADVERTISE_HOST` in `.env` (also
useful to advertise a stable hostname instead of an IP). If no LAN
interface exists at all, it falls back to `"localhost"` and logs a
warning. Check `dashboard.log` (or the terminal, if run in the
foreground) after a (re)start to see which host it's advertising and
why.

## Host panel

A panel above the app grid shows this device's own vitals - IP,
connection state, CPU, RAM, and storage. It updates on two different
cadences, so that anything requiring a subprocess or a network
round-trip doesn't add latency to the frequent status poll:

- **IP** and **Connection state** are resolved on the same cadence as
  the manifest scan (dashboard startup, or clicking "Rescan") - network
  topology rarely changes, and determining it involves finding the
  default gateway and pinging it once. That ping is **strictly local**
  (this device's own LAN gateway) - never anything internet-bound,
  consistent with this repo's offline-first design. Connection state is
  one of:
  - **Connected** (green) - has a LAN IP and the gateway responded.
  - **Link up** (amber) - has a LAN IP, but no gateway was found or it
    didn't respond to a ping.
  - **No network detected** (red) - no non-internal LAN IP at all (see
    "Reachable from other devices on the LAN" above).
- **CPU usage** is sampled in the background every
  `DASHBOARD_STATUS_POLL_INTERVAL_SECONDS` (a delta between two
  `os.cpus()` snapshots, not a load average) and cached - each request
  just reads the cached value, so it never blocks a request. It uses the
  same interval as the browser's status poll (see `.env.example`)
  rather than a separate hardcoded schedule. It briefly shows
  "measuring…" for the first cycle after startup until two samples
  exist.
- **RAM** and **Storage** (root filesystem, `df -kP /`) are computed
  fresh on every request/poll - both are cheap, instant reads with no
  need for caching.

## How status/start/stop works

- **Status** is read directly from `podman ps` for each app's
  compose-project label (`io.podman.compose.project=<id>`) - "running"
  if any container in that project is up, "stopped" if the project has
  no running containers, "not installed" if the app never appears in
  the repo-root `.installed` marker file. This is more reliable than an
  HTTP reachability check, since it can tell "still starting" apart from
  "not installed" apart from "crashed". Unlike the manifest scan, this
  check runs on every `GET /api/status` poll (cheap - it's just `podman
  ps`), so running/stopped state is always current without needing a
  rescan.
- **Start/Stop buttons** POST to `/apps/:id/start` or `/apps/:id/stop`,
  which run that app's own `apps/<id>/up.sh` / `down.sh` - the same
  scripts you'd run by hand. Apps that aren't installed yet show no
  buttons, just a hint to run their `install.sh` first (installing an
  app from the dashboard itself is out of scope - it can involve
  interactive prompts, large downloads, etc. that don't fit a button
  click).
- The browser polls `GET /api/status` every
  `DASHBOARD_STATUS_POLL_INTERVAL_SECONDS` (see `.env.example`) to keep
  the grid current, and immediately after any start/stop action. This
  does not re-scan manifests (see above).
- A malformed `manifest.json` (invalid JSON, or missing a required
  field) is skipped with a warning logged server-side rather than
  crashing the dashboard or the scan of every other app.

## No authentication

Consistent with the rest of this repo (see `docs/ARCHITECTURE.md`), the
dashboard assumes a private/trusted LAN and has no login. Anyone who can
reach its port can start/stop any app that ships a `manifest.json`. If
you expose this more broadly, put an auth-capable reverse proxy or VPN
in front.

## Files

```
server.js              Fastify app + routes (/, /api/status, /api/rescan, /apps/:id/start|stop)
lib/registry.js         scans apps/<id>/manifest.json, resolves live port from each app's .env
lib/network.js          determines the LAN host advertised in every app's URL
lib/hostinfo.js          IP/connection/CPU/RAM/storage for the Host panel
lib/status.js           installed/running checks + start/stop via other apps' scripts
views/                  Handlebars templates (layout, index, card partial)
public/                 style.css + client-side JS (filtering, polling, icons)
install.sh / up.sh /
  down.sh / uninstall.sh   host-process lifecycle (not podman-compose - see above)
.env.example            DASHBOARD_PORT, DASHBOARD_HOST, DASHBOARD_ADVERTISE_HOST,
                         DASHBOARD_SYSTEM_NAME, DASHBOARD_LOCATION,
                         DASHBOARD_STATUS_POLL_INTERVAL_SECONDS
```

## Notes for offline/low-power use

- No external fonts, CDNs, or analytics - `npm install` pulls its
  (small) dependency set once during setup; no runtime network calls
  except to the other apps' own host:port for status checks and
  start/stop.
- Flat, low-animation UI, respects `prefers-reduced-motion`.
- Works on a phone or tablet screen if that's what's available.

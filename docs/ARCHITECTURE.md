# Architecture

## Overview

catasophie is a collection of independent, offline-capable apps. There
is intentionally no central dashboard, orchestrator, or reverse proxy:
each app is its own Podman Compose project, started and stopped
independently, and reachable directly on its own published host
port(s).

```
                  Host Device (Pi / Mini PC / Laptop)
 ┌───────────────────────────────────────────────────────────────────┐
 │                            Podman                                  │
 │                                                                     │
 │   ┌─────────────────────┐   ┌────────────────────┐   ┌─────────────────┐   │
 │   │ apps/offline-maps   │   │ apps/wikimed       │   │ apps/translate  │   │
 │   │ tiles + web         │   │ kiwix-serve        │   │ libretranslate  │   │
 │   │ (routing/geocoder   │   │ (survival medicine │   │ (offline ML    │   │
 │   │  disabled for now)  │   │  ZIMs by default)  │   │  translation)  │   │
 │   └──────────┬──────────┘   └─────────┬──────────┘   └────────┬────────┘   │
 └──────────────┼─────────────────────────┼───────────────────────┼──────────┘
                │ :3010 (web)             │ :3020 (kiwix)         │ :3030
                │ :3012 (tiles)           │                       │
                ▼                         ▼                       ▼
          http://<device-ip>:<port>/  (LAN or localhost)
```

## Request flow

1. A client (phone/laptop) connects to the device's LAN/WiFi and browses
   directly to `http://<device-ip>:<port>/` for whichever app/service it
   wants (e.g. `:3010` for the maps frontend, `:3020` for the offline
   Kiwix reference content).
2. Each container publishes its port straight to the host - no routing,
   discovery, or path-rewriting layer in between.
3. Where a frontend needs to call sibling services (e.g. offline-maps'
   static page calling its tiles backend), it does so
   directly by port, using a small `config.js` rendered from `.env` at
   container start (see `apps/offline-maps/templates/config.js.template`).

## Why this design

- **Independent apps, zero shared infrastructure**: adding, removing, or
  updating an app never requires touching anything outside that app's
  own folder - no proxy config, no shared network, no label conventions
  to keep in sync.
- **No auth layer in this first version**: this repo is intended for a
  device on a private/trusted LAN (e.g. its own WiFi hotspot). If you
  expose it more broadly, put an auth-capable reverse proxy or VPN in
  front, or add per-app auth.
- **Independent compose projects, not one big compose file**: keeps
  resource-heavy apps separately startable/stoppable on
  constrained hardware, and keeps each app's README/scripts self-contained.
- **Each app has its own private Podman network** (compose's default
  per-project network) purely for its own internal container-to-container
  calls when it has more than one service (e.g. `offline-maps`' `web`
  calling its `tiles` service) - there's no cross-app shared network,
  since nothing needs one without a central proxy.
- **No dynamic lazy-start**: apps are started explicitly, individually,
  via their own `./apps/<app-id>/up.sh` - simpler, at the cost of not
  auto-starting on first request.

## The dashboard: a deliberate, narrow exception

`apps/dashboard` is the one app that breaks the "independent container,
no shared infra, no orchestrator" rule above - on purpose, and narrowly:

- It's a plain Node/Fastify process that runs **directly on the host**,
  not inside a container - it has no `docker-compose.yml` and isn't
  started via `podman-compose`. `install.sh`/`up.sh`/`down.sh` instead
  manage it as a regular background process (PID file, `nohup`).
- It discovers which apps to show by scanning each app directory for a
  `manifest.json` (see `docs/ADDING_AN_APP.md`) rather than a
  hand-maintained registry - an app that ships one appears automatically,
  no separate registration step, and one that doesn't (like
  `apps/_template`, `apps/cli`, or the dashboard itself) simply doesn't
  show up. This scan happens once at startup and again whenever the
  dashboard's "Rescan" button is used - not on every request.
- It reads each other app's status by inspecting `podman ps` for that
  app's compose-project label, and starts/stops apps by invoking that
  app's own `up.sh`/`down.sh` - never `podman-compose` directly on
  another app's behalf. Every other app's own idempotent install
  contract (`docs/ADDING_AN_APP.md`) is completely unaffected; the
  dashboard is just a UI in front of the same scripts you'd run by hand.
- This was chosen over containerizing the dashboard and bind-mounting
  the podman socket + this repo into it, which would work but grants a
  container root-equivalent control over the whole host's podman and
  couples it to socket-path/rootless-vs-rootful details that vary by
  platform - a plain host process avoids all of that at the cost of
  being the only app in `apps/` that isn't itself a container.
- Like the rest of the repo, it has no authentication - anyone who can
  reach its port can start/stop any app it lists.

See `apps/dashboard/README.md` for the full rationale and how it works.

## Directory layout

See the top-level `README.md` for the full directory tree and
`docs/ADDING_AN_APP.md` for the per-app contract (which applies to every
app under `apps/` except `apps/dashboard`, see above).

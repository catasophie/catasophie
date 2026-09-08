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
 │   ┌─────────────────────┐   ┌────────────────────┐   ┌─────────┐  │
 │   │ apps/llm-survival    │   │ apps/offline-maps   │   │ apps/…  │  │
 │   │ ollama + webui +     │   │ tiles + web          │   │         │  │
 │   │ kiwix                │   │ (routing/geocoder    │   │         │  │
 │   │ (own private network)│   │  disabled for now)   │   │         │  │
 │   └──────────┬──────────┘   └──────────┬──────────┘   └─────────┘  │
 └──────────────┼──────────────────────────┼──────────────────────────┘
                │ :3001 (webui)            │ :3010 (web)
                │ :3002 (kiwix)            │ :3012 (tiles)
                ▼                          ▼
         http://<device-ip>:<port>/  (LAN or localhost)
```

## Request flow

1. A client (phone/laptop) connects to the device's LAN/WiFi and browses
   directly to `http://<device-ip>:<port>/` for whichever app/service it
   wants (e.g. `:3001` for the LLM chat UI, `:3010` for the maps
   frontend).
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
  front, or add per-app auth (Open WebUI has its own login, for example).
- **Independent compose projects, not one big compose file**: keeps
  resource-heavy apps (LLM, maps) separately startable/stoppable on
  constrained hardware, and keeps each app's README/scripts self-contained.
- **Each app has its own private Podman network** (compose's default
  per-project network) purely for its own internal container-to-container
  calls (e.g. `webui` talking to `ollama`) - there's no cross-app shared
  network, since nothing needs one without a central proxy.
- **No dynamic lazy-start**: apps are started explicitly via
  `catasophie up <app-id>` - simpler, at the cost of not auto-starting on
  first request.

## Directory layout

See the top-level `README.md` for the full directory tree and
`docs/ADDING_AN_APP.md` for the per-app contract.

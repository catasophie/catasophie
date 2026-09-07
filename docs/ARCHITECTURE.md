# Architecture

## Overview

catasophie is a collection of independent, offline-capable apps that sit
behind a single shared reverse proxy on a Podman network. There is
intentionally no central dashboard/orchestrator process: each app is its
own Podman Compose project, started and stopped independently, and
discovered automatically by the proxy via labels declared in its own
compose file.

```
                  Host Device (Pi / Mini PC / Laptop)
 ┌───────────────────────────────────────────────────────────────────┐
 │                  Podman (network: catasophie)                     │
 │                                                                     │
 │   ┌────────┐        ┌──────────┐                                  │
 │   │ proxy  │◄───────┤ landing  │  (root docker-compose.yml)         │
 │   │(Traefik)│       └──────────┘                                  │
 │   └───┬────┘                                                      │
 │       │ label-based auto-discovery (podman/docker provider)        │
 │       │                                                             │
 │   ┌───┴─────────────────┐   ┌────────────────────┐   ┌─────────┐  │
 │   │ apps/llm-survival    │   │ apps/offline-maps   │   │ apps/…  │  │
 │   │ ollama + webui +     │   │ osrm + tiles +      │   │         │  │
 │   │ kiwix                │   │ geocoder + web       │   │         │  │
 │   └─────────────────────┘   └────────────────────┘   └─────────┘  │
 └───────────────────────────────────────────────────────────────────┘
```

## Request flow

1. A client (phone/laptop) connects to the device's LAN/WiFi and browses
   to `http://catasophie.local/`.
2. Traefik (the single entrypoint) matches the request path against
   routers declared via container labels and forwards it to the matching
   app's service.
3. Each app's compose file declares its own Traefik labels
   (`traefik.http.routers.<name>.rule=PathPrefix(...)`) - Traefik's
   Podman/Docker provider watches the shared network and picks these up
   automatically, with no central proxy config file to edit.

## Why this design

- **Independent apps, zero-touch proxy config**: adding, removing, or
  updating an app never requires editing the proxy - only that app's own
  compose file (labels + network membership).
- **No auth layer in this first version**: this repo is intended for a
  device on a private/trusted LAN (e.g. its own WiFi hotspot). If you
  expose it more broadly, put an auth-capable reverse proxy or VPN in
  front, or add per-app auth (Open WebUI has its own login, for example).
- **Independent compose projects, not one big compose file**: keeps
  resource-heavy apps (LLM, maps) separately startable/stoppable on
  constrained hardware, and keeps each app's README/scripts self-contained.
- **No dynamic lazy-start**: unlike a dashboard-managed setup, apps here
  are started explicitly via `scripts/up.sh <app-id>` - simpler, at the
  cost of not auto-starting on first request.

## Directory layout

See the top-level `README.md` for the full directory tree and
`docs/ADDING_AN_APP.md` for the per-app contract.

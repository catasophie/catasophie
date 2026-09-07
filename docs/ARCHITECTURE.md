# Architecture

## Overview

catasophie is a self-hosted, containerized "personal infrastructure box"
meant to keep working when the power grid or internet is down. It runs on
a Raspberry Pi, mini PC, or laptop, optionally broadcasts its own WiFi
hotspot, and hosts a growing set of offline-capable tools behind a single
web dashboard.

```
                     Host Device (Pi / Mini PC / Laptop)
 ┌──────────────┐      ┌──────────────────────────────────────────────┐
 │ hostapd +    │      │              Podman (network: catasophie)     │
 │ dnsmasq      │      │                                                │
 │ (WiFi AP,    │      │  ┌────────┐  ┌────────┐  ┌───────────────┐   │
 │  host-level) │      │  │ proxy  │──│  auth  │  │   dashboard    │   │
 └──────────────┘      │  │(Caddy) │  │(Authelia)│ │ (FastAPI+HTMX) │  │
                        │  └────┬───┘  └────────┘  └───────┬───────┘   │
                        │       │ forward_auth               │          │
                        │       └─────────────────────────────┘          │
                        │                     │ dynamic reverse-proxy    │
                        │                     │ + lazy-start             │
                        │        ┌────────────┼────────────┐            │
                        │        ▼            ▼            ▼            │
                        │   ┌────────┐  ┌───────────┐  ┌─────────┐      │
                        │   │  maps  │  │llm-knowledge│ │ radio   │ ...  │
                        │   └────────┘  └───────────┘  └─────────┘      │
                        └──────────────────────────────────────────────┘
```

## Request flow

1. A client (phone/laptop) connects to the device's WiFi hotspot (or LAN)
   and browses to the dashboard.
2. Caddy (the single entrypoint / reverse proxy) forward-auths every
   request to Authelia. Authelia handles login and issues a session; on
   success it forwards `Remote-User` / `Remote-Groups` headers through.
3. Requests land on the dashboard (FastAPI). For `/tools/<id>/*` paths,
   the dashboard:
   - checks the tool's `manifest.json` for `required_role` and compares
     against the caller's `Remote-Groups` (fine-grained per-tool
     authorization lives here, not in Authelia's static config, since the
     set of tools/manifests changes at runtime)
   - lazy-starts the tool's container via `podman-compose up -d` if it
     isn't already running
   - reverse-proxies the request to the tool's container over the shared
     `catasophie` Podman network

This means Authelia only needs a coarse, static access-control policy
("must be logged in"), while all per-tool authorization and container
lifecycle management is handled dynamically by the dashboard as tools are
added/removed.

## Why this design

- **Single entrypoint, dynamic tools**: new tools are added by dropping a
  folder into `tools/` (see `docs/PLUGIN_SPEC.md`) — no changes to the
  proxy or auth config are needed, because the dashboard discovers
  manifests at request time and handles routing/auth itself.
- **Lazy-start**: on constrained hardware (Raspberry Pi) you don't want
  the LLM, maps, and radio stacks all running simultaneously. Tools
  default to `autostart: false` and start on first access, or can be
  explicitly started/stopped from the dashboard.
- **Offline-first auth**: Authelia is entirely file-based (no external
  DB, no SMTP, no OAuth provider) so login works with zero internet
  connectivity.
- **Host-level networking**: WiFi AP mode (`hostapd`/`dnsmasq`) runs on
  the host, not in a container, because it needs raw access to the
  wireless interface that Podman can't easily provide.

## Directory layout

See the top-level `README.md` for the full directory tree and
`docs/PLUGIN_SPEC.md` for the tool manifest contract.

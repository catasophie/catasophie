# catasophie

A self-hosted collection of offline-capable apps/tools that keep working
when the power grid or internet is down. Runs on a Raspberry Pi, mini PC,
or laptop via Podman; each app is independent and gets picked up
automatically by a shared reverse proxy.

## Status

First version: reverse proxy + landing page, an offline LLM assistant
with a curated survival/medical reference corpus (`apps/llm-survival`),
and offline maps with basic driving navigation (`apps/offline-maps`). See
`docs/ROADMAP.md` for other apps worth adding next (offline encyclopedia,
mesh comms, SDR radio monitor, inventory tracker, ...).

## Quick start

Requires [Podman](https://podman.io/docs/installation) and
[podman-compose](https://github.com/containers/podman-compose).

```sh
./scripts/up.sh                            # network + reverse proxy + landing page
./scripts/up.sh llm-survival offline-maps  # also start both apps
```

Then open `http://catasophie.local/` (or `http://<device-ip>/`) for the
landing page linking to each running app. See each app's own README for
one-time setup (model pulls, corpus ingestion, map region import) before
it's usable:

- [`apps/llm-survival/README.md`](apps/llm-survival/README.md)
- [`apps/offline-maps/README.md`](apps/offline-maps/README.md)

Stop everything with `./scripts/down.sh [app-ids...]`.

## Repository layout

```
catasophie/
├── docker-compose.yml     # shared network + Traefik reverse proxy + landing page
├── proxy/                  # Traefik static config + landing page HTML
├── apps/
│   ├── llm-survival/       # offline LLM + survival/medical RAG corpus
│   ├── offline-maps/       # offline maps + basic navigation
│   └── _template/          # copy this to scaffold a new app
├── scripts/
│   ├── up.sh / down.sh      # start/stop the proxy and named apps
│   └── add-app.sh           # scaffold a new app from _template
└── docs/
    ├── ARCHITECTURE.md
    ├── ADDING_AN_APP.md
    └── ROADMAP.md
```

## Adding a new app

```sh
./scripts/add-app.sh my-tool /my-tool/ 8000
```

See `docs/ADDING_AN_APP.md` for the full convention (network, labels, data
directory). The reverse proxy needs no configuration changes - it
discovers new apps automatically from labels in their own compose file.

## Design docs

- `docs/ARCHITECTURE.md` - how routing/discovery works and why
- `docs/ADDING_AN_APP.md` - the app contract (network, labels, data)
- `docs/ROADMAP.md` - candidate future apps/tools

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
./scripts/install.sh
```

This starts the core network + reverse proxy, lets you pick which app(s)
to install (checkbox menu via `whiptail`/`dialog` if available, plain
numbered prompt otherwise), and walks each selected app's own installer -
asking only for configuration that isn't already set (model choice, map
region, API keys, etc). Re-run it any time to install additional apps or
finish a step you skipped.

Then open `http://catasophie.local:8080/` (or `http://<device-ip>:8080/`) for
the landing page linking to each running app. `PROXY_HTTP_PORT` defaults to
8080 because rootless Podman can't bind port 80 without extra setup - see
the comment in `.env.example` if you want plain port 80.

Most apps are reachable under a path (`/maps/`, etc.), but `llm-survival`'s
web UI is routed by hostname instead (`llm.catasophie.local`) because its
frontend can't be mounted under a path prefix - add it to `/etc/hosts`
alongside `catasophie.local` (see `apps/llm-survival/README.md`).

Prefer to do it by hand? See each app's own README:

- [`apps/llm-survival/README.md`](apps/llm-survival/README.md)
- [`apps/offline-maps/README.md`](apps/offline-maps/README.md)

Stop everything with `./scripts/down.sh [app-ids...]`. Update installed
apps (and pull latest repo changes) with `./scripts/update.sh` - it
automatically backs up each app before updating and rolls back
automatically if the update leaves it unhealthy. See
`docs/BACKUP_RESTORE.md` for manual backup/restore usage.

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
│   ├── install.sh           # root wizard: pick + install app(s)
│   ├── update.sh             # git pull + update apps, with auto backup/rollback
│   ├── backup.sh / restore.sh # manual backup + restore (data/volumes/.env)
│   ├── up.sh / down.sh        # start/stop the proxy and named apps
│   ├── add-app.sh             # scaffold a new app from _template
│   └── lib/common.sh          # shared install/backup/restore helpers
└── docs/
    ├── ARCHITECTURE.md
    ├── ADDING_AN_APP.md
    ├── BACKUP_RESTORE.md
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
- `docs/BACKUP_RESTORE.md` - backup/restore + automatic update rollback
- `docs/ROADMAP.md` - candidate future apps/tools

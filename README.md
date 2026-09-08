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

Requires [Podman](https://podman.io/docs/installation), Bash 4+, and
[podman-compose](https://github.com/containers/podman-compose).

**Linux** (incl. Raspberry Pi): install `podman` and `podman-compose` via
your distro's package manager. Bash 4+ is standard on any current distro.

**macOS**: install everything via Homebrew, then start the podman VM once:

```sh
brew install podman podman-compose bash
podman machine init
podman machine start
```

macOS ships bash 3.2 at `/bin/bash`, which these scripts can't use
(no `mapfile`/associative arrays). Either put the Homebrew bash ahead of
`/bin/bash` on your `PATH`, or invoke scripts with it explicitly:

```sh
$(brew --prefix)/bin/bash scripts/install.sh
```

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

Uninstall with `./scripts/uninstall.sh` - it asks for confirmation, then
removes containers/volumes, data directories, backups, `.env` files, and
the shared network, restoring the repo to its state before
`scripts/install.sh` was ever run:

```sh
./scripts/uninstall.sh                       # everything (full reset)
./scripts/uninstall.sh llm-survival           # just one app
./scripts/uninstall.sh --keep-data            # keep data directories
./scripts/uninstall.sh --keep-backups         # keep backups/
./scripts/uninstall.sh --yes                  # skip confirmation
```

Each app also ships its own `apps/<app-id>/uninstall.sh` (same flags),
which the root script calls under the hood - run it directly to remove
just that app without touching anything else.

## Storing data on an external drive

Each app's installer prompts for `DATA_DIR` - leave it blank to keep
data (ollama models, webui data, kiwix, map tiles/routing graphs, etc.)
in `./data` next to the app, or set it to an absolute path to store it
elsewhere, e.g. a USB/external drive mounted at `/mnt/external`:

```
DATA_DIR=/mnt/external/catasophie/llm-survival
```

Create the base folder on the drive (e.g. `mkdir -p
/mnt/external/catasophie`) once the drive is mounted - the installer
creates the app-specific subfolder under it, but refuses to create the
mount point itself (to avoid silently writing to the boot disk if the
drive isn't mounted). You can also set `DATA_DIR` by hand in
`apps/<app-id>/.env` before running the installer. See
`docs/ADDING_AN_APP.md` for the convention if you're adding a new app.

## Troubleshooting

**404 on an app's URL, but the container is running**: Traefik
discovers routes by watching the Podman API socket - check `podman logs
catasophie_proxy_1` for `providerName=docker` errors:
- `permission denied ... docker.sock`: the socket is owned by
  root/SELinux-labeled for the podman service only. `docker-compose.yml`
  already sets `security_opt: label=disable` on the `proxy` service to
  cover this (relevant on any SELinux-enforcing host, including the
  Fedora CoreOS VM that `podman machine` runs on macOS) - if you're
  still hitting this, make sure you're on a version of this repo with
  that fix.
- `connection refused` / `no such file or directory`: `PODMAN_SOCK` in
  the root `.env` points at the wrong socket. On macOS specifically, it
  must be the path *inside* the podman machine VM (typically
  `/run/podman/podman.sock`), not the host-side API-forwarding socket
  from `podman machine inspect` - containers (including Traefik) run
  inside the VM, so bind-mount sources are resolved there, not on the
  Mac host. Delete the `PODMAN_SOCK=` line from `.env` and re-run
  `./scripts/up.sh` to have it re-detected, then `podman-compose down &&
  podman-compose up -d` to pick up the change.

**Podman machine disk full** (`no space left on device` while pulling
an image, macOS only): the podman machine VM has its own fixed-size
virtual disk, separate from your Mac's actual free space. Grow it with:
```sh
podman machine stop
podman machine set --disk-size 60 podman-machine-default
podman machine start
```
If `df -h /` inside the VM (`podman machine ssh` then `df -h /`) still
shows the old size, the partition/filesystem needs growing too:
```sh
podman machine ssh podman-machine-default 'sudo growpart /dev/vda 4 && sudo xfs_growfs /var'
```

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
│   ├── uninstall.sh          # remove installed app(s), or everything
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

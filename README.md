# catasophie

A self-hosted collection of offline-capable apps/tools that keep working
when the power grid or internet is down. Runs on a Raspberry Pi, mini PC,
or laptop via Podman; each app is independent and reachable directly on
its own published port - no reverse proxy or shared network involved.

## Status

First version: an offline LLM assistant with a curated survival/medical
reference corpus (`apps/llm-survival`), and offline maps with basic
driving navigation (`apps/offline-maps`). See `docs/ROADMAP.md` for other
apps worth adding next (offline encyclopedia, mesh comms, SDR radio
monitor, inventory tracker, ...).

## Quick start

Requires [Podman](https://podman.io/docs/installation), Bash 4+, `make`,
and [podman-compose](https://github.com/containers/podman-compose).

**Linux** (incl. Raspberry Pi): install `podman`, `podman-compose`, and
`make` via your distro's package manager. Bash 4+ is standard on any
current distro.

**macOS**: install everything via Homebrew, then start the podman VM once:

```sh
brew install podman podman-compose bash make
podman machine init
podman machine start
```

macOS ships bash 3.2 at `/bin/bash`, which these scripts can't use
(no `mapfile`/associative arrays). Either put the Homebrew bash ahead of
`/bin/bash` on your `PATH`, or invoke scripts with it explicitly:

```sh
$(brew --prefix)/bin/bash apps/cli/scripts/install.sh
```

Then run the installer - either through `make`:

```sh
make install
```

or by calling the shell script directly:

```sh
./apps/cli/scripts/install.sh
```

This lets you pick which app(s) to install (checkbox menu via
`whiptail`/`dialog` if available, plain numbered prompt otherwise), and
walks each selected app's own installer (`apps/<app-id>/install.sh`) -
asking only for configuration that isn't already set (model choice, map
region, ports, etc). Re-run it any time to install additional apps or
finish a step you skipped.

Each app publishes its own port(s) directly - no shared entrypoint or
landing page. After installing, each app's installer prints the URL to
visit, e.g. `http://localhost:3010/` for `offline-maps`'s web UI, or
`http://<device-ip>:3010/` from another device on the LAN. See each
app's own README for its full list of ports:

- [`apps/offline-maps/README.md`](apps/offline-maps/README.md)

Stop everything with `make down ARGS="<app-ids...>"` (or
`./apps/cli/scripts/down.sh <app-ids...>`). Update installed apps (and
pull latest repo changes) with `make update` (or
`./apps/cli/scripts/update.sh`) - it automatically backs up each app
before updating and rolls back automatically if the update leaves it
unhealthy. See `docs/BACKUP_RESTORE.md` for manual backup/restore usage.

Uninstall with `make uninstall` (or
`./apps/cli/scripts/uninstall.sh`) - it asks for confirmation, then
removes containers/volumes, data directories, backups, and `.env` files,
restoring the repo to its state before `make install` was ever run:

```sh
make uninstall                                         # everything (full reset)
make uninstall ARGS="offline-maps"                      # just one app
make uninstall ARGS="--keep-data"                       # keep data directories
make uninstall ARGS="--keep-backups"                     # keep backups/
make uninstall ARGS="--yes"                              # skip confirmation
make uninstall ARGS="--with-images"                      # also remove pulled images
```

Each app also ships its own `apps/<app-id>/uninstall.sh` (same flags),
which `apps/cli/scripts/uninstall.sh` calls under the hood - run it
directly to remove just that app without touching anything else.

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
├── apps/
│   ├── offline-maps/       # offline maps + basic navigation
│   ├── _template/          # copy this (via `make add-app`) to scaffold a new app
│   └── cli/                # shell scripts driving install/uninstall/up/down/update/backup/restore
│       └── scripts/
│           ├── install.sh           # root wizard: pick + install app(s)
│           ├── uninstall.sh          # remove installed app(s), or everything
│           ├── update.sh             # git pull + update apps, with auto backup/rollback
│           ├── backup.sh / restore.sh # manual backup + restore (data/volumes/.env)
│           ├── up.sh / down.sh        # start/stop named apps
│           ├── add-app.sh             # scaffold a new app from _template
│           └── lib/common.sh          # shared install/backup/restore helpers
└── docs/
    ├── ARCHITECTURE.md
    ├── ADDING_AN_APP.md
    ├── BACKUP_RESTORE.md
    └── ROADMAP.md
```

## Adding a new app

```sh
make add-app ARGS="my-tool 8000"
# or: ./apps/cli/scripts/add-app.sh my-tool 8000
```

See `docs/ADDING_AN_APP.md` for the full convention (published port,
data directory, install/uninstall scripts).

## Design docs

- `docs/ARCHITECTURE.md` - how each app is structured and why
- `docs/ADDING_AN_APP.md` - the app contract (ports, data, install/uninstall)
- `docs/BACKUP_RESTORE.md` - backup/restore + automatic update rollback
- `docs/ROADMAP.md` - candidate future apps/tools

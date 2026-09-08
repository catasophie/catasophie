# AGENTS.md

Instructions for AI coding agents (and anyone else) working in this
repository. Read this before making changes.

## Project goal

catasophie is a self-hosted collection of offline-capable apps/tools
meant to keep working when the power grid or internet is down - e.g.
during a natural disaster, extended outage, or other catastrophe. It's
designed to run on modest, portable hardware (a Raspberry Pi, mini PC,
or laptop) via Podman, entirely without an internet connection once
set up. Every app in this repo should work standalone on a device with
no network access beyond its own local WiFi/LAN.

This shapes a lot of decisions: apps should minimize ongoing external
dependencies (no "phone home", no cloud APIs at runtime), heavy
one-time setup (model downloads, map tile builds, ZIM downloads) is
expected and should be resumable/idempotent, and content choices should
lean toward what's actually useful in a survival/emergency context
(e.g. `apps/wikimed` defaults to a compact *survival* medicine guide,
not the full general medical encyclopedia).

## Repository structure

```
catasophie/
├── apps/
│   ├── <app-id>/           # one independent Podman Compose project per app
│   │   ├── docker-compose.yml
│   │   ├── install.sh / uninstall.sh
│   │   ├── up.sh / down.sh
│   │   ├── .env.example
│   │   ├── README.md
│   │   └── scripts/        # optional: heavy one-time setup (downloads, imports)
│   ├── _template/          # scaffold source for `make add-app`
│   └── cli/scripts/        # root-level install/uninstall/update/backup/restore wizards
│       └── lib/common.sh   # shared bash helpers (prompts, backup/restore, step-tracking)
├── docs/
│   ├── ARCHITECTURE.md     # why the "no shared proxy, independent apps" design
│   ├── ADDING_AN_APP.md    # the per-app contract - READ THIS before adding/changing an app
│   ├── BACKUP_RESTORE.md   # backup/restore + automatic update rollback
│   └── ROADMAP.md          # candidate future apps
├── README.md
└── AGENTS.md               # this file
```

Every app under `apps/` (except `_template`) is a **fully independent**
Podman Compose project, reachable directly on its own published host
port(s). There is intentionally **no reverse proxy, no shared network,
no central dashboard** - see `docs/ARCHITECTURE.md` for the reasoning.
Currently implemented apps: `apps/offline-maps`, `apps/wikimed`. See
`README.md`'s "Status" section for the current list (keep it updated -
see "Keeping docs in sync" below).

## The app contract (summary - `docs/ADDING_AN_APP.md` is authoritative)

Every app must ship, at minimum:

- `docker-compose.yml` - publishes port(s) directly via
  `${MY_APP_PORT:-<default>}:<container-port>`, no labels/proxy config
- `install.sh` - idempotent, prompts only for unset config (via
  `prompt_if_unset`/`prompt_choice_if_unset`/`prompt_multi_choice_if_unset`
  from `apps/cli/scripts/lib/common.sh`), starts containers, calls
  `mark_installed <app-id>`
- `uninstall.sh` - stops/removes containers+volumes+data+backups+`.env`,
  supports `--yes`/`--keep-data`/`--keep-backups`/`--with-images`
- `up.sh` / `down.sh` - simple start/stop, argumentless, idempotent
- `.env.example` - documents every configurable variable
- `README.md` - what it does, ports, one-time setup steps

Persistent data goes under `${DATA_DIR:-./data}` inside the app folder
(bind mount, not a named volume, when practical) so users can redirect
it to an external drive. Heavy one-time setup (downloads, builds) should
live in its own script under `apps/<id>/scripts/`, be resumable (final
output written via temp-file-then-atomic-rename), and use
`mark_step_done`/`step_done`/`clear_step` for multi-stage tracking.
`apps/offline-maps/scripts/import-region.sh` and
`apps/wikimed/scripts/download-zim.sh` are the two real reference
examples to copy patterns from.

**Adding a new app**: run `make add-app` (scaffolds from `apps/_template/`
with your id/port substituted), then follow `docs/ADDING_AN_APP.md`.

## How apps are installed/started/stopped/updated

```sh
make install                          # interactive wizard, pick app(s)
make install ARGS="offline-maps"      # install a specific app non-interactively

./apps/<app-id>/up.sh                 # start one app directly
./apps/<app-id>/down.sh                # stop one app directly

make update                           # update all installed apps (auto backup + rollback on failure)
make backup / make restore            # manual backup/restore (see docs/BACKUP_RESTORE.md)
make uninstall                        # remove everything, or ARGS="<app-id>" for just one
```

There is no "start everything" or "stop everything" command by design -
apps are managed individually. See `README.md`'s "Quick start" for the
full walkthrough.

## Mandatory verification checklist before considering an app change done

**Do not trust `podman-compose up -d`'s exit code alone.** A container
can report success and then immediately exit or crash-loop while being
completely non-functional. Concretely, for anything you touch in an
app's `docker-compose.yml`, `install.sh`, or setup scripts:

1. `podman-compose -f apps/<id>/docker-compose.yml config` - validates
   compose syntax/interpolation before anything starts.
2. Start it, wait a few seconds, then check every container is actually
   still `Up` (not `Exited`, even `Exited (0)`):
   ```sh
   podman-compose -f apps/<id>/docker-compose.yml up -d
   sleep 5
   podman ps -a --filter "label=io.podman.compose.project=<id>"
   ```
3. **Read the logs**, especially the first few lines right after start
   (`podman logs <container>`) - this is where entrypoint scripts print
   the actual command they ran. Watch for images whose entrypoint
   already injects its own flags (e.g. `kiwix-serve`'s Docker image
   auto-adds `--port=$PORT` itself - passing `--port` again in
   `command:` causes a duplicate-flag error that silently kills the
   container). **Read the image's actual entrypoint/start script
   source**, not just a `docker run` example from its README, before
   assuming which flags/args are safe to pass yourself.
4. **Actually hit the published port** with `curl` and check the
   response is real content, not just a 200:
   ```sh
   curl -sS -o /dev/null -w "HTTP %{http_code}\n" http://localhost:<port>/
   ```
5. Re-run `install.sh`/`up.sh` a second time and confirm it's a clean
   no-op (no re-prompting, no errors) - idempotency is part of the
   contract.
6. Clean up test containers/data afterward
   (`./apps/<id>/down.sh` or `uninstall.sh --yes`).

The full version of this checklist lives in `docs/ADDING_AN_APP.md`
under "Testing your app" - keep both in sync if you refine it.

## Known gotchas / lessons learned

- **Container entrypoints often add their own flags.** Don't assume a
  `docker run ... --some-flag` example from an image's README translates
  directly into your `command:` - the image's own entrypoint/start
  script may already construct part of the command line (ports, paths,
  etc). Check the actual entrypoint script source when in doubt.
- **Exec-form `command:` arrays are not shell-interpreted.** A glob like
  `*.zim` only expands if the containerized program itself implements
  globbing (verify this - `kiwix-serve` does, most programs don't).
- **Bash 4+ is required** (`apps/cli/scripts/lib/common.sh` uses
  associative arrays and `mapfile`). macOS ships bash 3.2 at
  `/bin/bash` - see `README.md`'s macOS quick-start section.
- **`podman-compose config`** is a fast way to catch YAML/interpolation
  mistakes before wasting time pulling images or downloading data.

## Keeping docs in sync

When you add, remove, or change the status of an app, update all of:

- `README.md` - "Status" section and repository layout tree
- `docs/ARCHITECTURE.md` - the diagram, if published ports change
- `docs/ADDING_AN_APP.md` / `docs/BACKUP_RESTORE.md` - any inline
  example commands referencing specific app ids
- `docs/ROADMAP.md` - remove an item once it's actually implemented

Stale references to not-yet-built apps described as if already working
are actively misleading (this file exists partly because that happened
once already in this repo's history) - prefer describing only what
actually exists in `apps/`, and keep aspirational/future work confined
to `docs/ROADMAP.md`.

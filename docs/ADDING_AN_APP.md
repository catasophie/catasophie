# Adding an App

Every app lives in `apps/<app-id>/` and is a fully independent Podman
Compose project, reachable directly on its own published port(s) - no
shared proxy or network involved.

> **Exception**: `apps/dashboard` does not follow this contract - it's a
> plain host process (not a container) that starts/stops the other apps
> listed above by calling their own `up.sh`/`down.sh`. See
> `apps/dashboard/README.md` and the "dashboard" section of
> `docs/ARCHITECTURE.md` for why. Everything below describes the
> contract for every other app.

> **Adding a third-party app instead?** If you want to run something
> that isn't (and won't be) part of this repo - found online, or your
> own - see `docs/EXTERNAL_APPS.md` instead: `apps/external/<id>/` uses
> a loosened version of this contract (only `docker-compose.yml` +
> `manifest.json` are required) and is gitignored entirely, since it's
> manually cloned in by the user rather than committed here.

```sh
make add-app
# or: ./apps/cli/scripts/add-app.sh
```

This prompts for an app id and a default port, then copies
`apps/_template/` to `apps/<app-id>/` and substitutes both into the
compose file, install/uninstall/up/down scripts, `.env.example`, and
README (including deriving a valid `SCREAMING_SNAKE_CASE` port env var
name from the id, e.g. `MY_TOOL_PORT` for `my-tool`).

## Contract

- **Published port(s)**: publish your service(s) directly on the host,
  with a sensible default that's overridable via `.env` (mirroring the
  existing apps' convention, e.g. `LLM_WEBUI_PORT`, `MAPS_TILES_PORT`):
  ```yaml
  ports:
    - "${MY_TOOL_PORT:-8000}:8000"
  ```
  Pick a default port that doesn't collide with existing apps (see each
  app's `.env.example` for what's already taken). No labels, discovery,
  or central config needed - just a normal compose `ports:` mapping.
- **Data**: persistent data goes under `${DATA_DIR:-./data}/` inside the
  app folder (the default `./data` is already gitignored via the root
  `**/data/` pattern), or as named volumes declared in a standard
  top-level `volumes:` block in your `docker-compose.yml`. Prefer the
  `DATA_DIR`-driven bind mount over named volumes when practical - it
  lets users redirect the app's data to an external drive by setting
  `DATA_DIR=/absolute/path` in the app's `.env` (see
  `apps/_template/install.sh` for the prompt/`ensure_data_dir` pattern).
  Both bind mounts and named volumes are picked up automatically by
  `make backup`/`make restore` - no extra config needed, as long as
  volume names follow the normal top-level `volumes:` convention (see
  `docs/BACKUP_RESTORE.md`).
- **Multiple services calling each other**: if your app has a frontend
  that needs to call sibling backend services directly (since there's no
  proxy to unify them under one origin/path), have it learn their ports
  at runtime rather than hardcoding them. See
  `apps/offline-maps/templates/config.js.template` +
  `docker-compose.yml`'s `web` service for a working pattern: nginx's
  built-in `docker-entrypoint.d/20-envsubst-on-templates.sh` renders a
  template into `config.js` from environment variables at container
  start, and the page reads `window.MAPS_CONFIG.<x>Port` +
  `location.hostname` to build each backend's URL.
- **README.md**: document what the app does, how to run it, its
  published port(s), and any one-time setup (model downloads, data
  imports, etc.) - keep heavy setup steps as explicit scripts, not
  something that runs automatically.
- **manifest.json**: every app must ship a `manifest.json` describing
  itself for `apps/dashboard` - the dashboard discovers apps by scanning
  `apps/<id>/manifest.json` at startup (and on demand via its "Rescan"
  button), not from a hand-maintained list, so an app with no
  `manifest.json` simply never shows up there (this is how
  `apps/_template`, `apps/cli`, and `apps/dashboard` itself stay off the
  dashboard without any special-casing). Schema:
  ```json
  {
    "name": "Offline Maps",
    "description": "One short sentence, shown on the dashboard card.",
    "category": "Navigation",
    "icon": "map",
    "protocol": "http",
    "path": "/",
    "port": { "envVar": "MAPS_WEB_PORT", "default": 3010 }
  }
  ```
  `name`, `description`, `category`, `icon`, and `port` (with both
  `port.envVar` and `port.default`) are required; `protocol`/`path`
  default to `"http"`/`"/"` if omitted. There's no per-app `host` field -
  every app runs on the same device as the dashboard, so the host part of
  each app's URL comes from a single dashboard-wide setting instead (see
  `apps/dashboard/README.md`'s `DASHBOARD_ADVERTISE_HOST`), not something
  each manifest repeats. `icon` must be one of the keys in
  `apps/dashboard/public/app.js`'s `ICONS` map (falls back to `"server"`
  if unknown). The dashboard reads the actual port live from the app's
  own `.env` at scan time (via `port.envVar`), falling back to
  `port.default` if `.env` or that var is missing (e.g. before the app is
  installed) - the app's `.env` stays the single source of truth for its
  port, the manifest never hardcodes a value that could drift from it. A
  malformed manifest is skipped with a logged warning rather than
  crashing the dashboard.
  `apps/_template/manifest.json` has a placeholder to copy from - `make
  add-app` scaffolds it automatically with the id/port substituted in,
  same as the other template files (edit `description`/`category`/
  `icon` by hand afterward).
- **.env.example**: if your app needs configuration, provide an
  `.env.example` in the app folder; `up.sh` copies it to `.env` on
  first start if missing.
- **install.sh**: every app must ship an `install.sh` (this is what
  `make install`'s wizard calls). Contract:
  - `source` `apps/cli/scripts/lib/common.sh` for shared helpers
  - `check_deps` at the top
  - `ensure_env_file "$APP_DIR"` then use `prompt_if_unset VAR "prompt text" "default" "$ENV_FILE"`
    for each required setting - it must be a no-op if the variable is
    already set, so re-running the installer never re-asks answered
    questions
  - use `confirm "question"` before any heavy/slow step (large downloads,
    long-running imports)
  - start the app's containers (`podman-compose -f docker-compose.yml up -d`)
  - call `mark_installed <app-id>` at the end so `make update` picks
    it up automatically
  - must be safe to re-run (idempotent)
  - for any step that's heavy, externally-fallible, or has multiple
    sub-stages (API calls that can be rejected, per-item processing,
    multi-stage builds), use `mark_step_done <app-id> <step-name>` /
    `step_done <app-id> <step-name>` / `clear_step <app-id> <step-name>`
    (backed by `apps/<id>/.install-steps`, gitignored) so a re-run
    resumes from wherever it left off instead of blindly redoing
    everything or - worse - silently skipping a step that only
    *partially* completed. Prefer this over a coarse "does some output
    directory have anything in it" check, which can't tell a fully
    finished step from one that crashed partway through. Two real
    examples in this repo:
    - `apps/offline-maps/scripts/import-region.sh` builds its vector
      tiles into a temporary `.building` location, only moving into the
      final path after the build fully succeeds - so "the final file
      exists" reliably means "this step actually finished", and a crash
      partway through gets cleanly retried on the next run instead of
      being mistaken for already done. It's also a good example of a
      heavy per-app script that owns its own required-input prompting
      (`MAP_SOURCE`/`MAP_REGION`/`MAP_SOURCE_URL`, persisted to this
      app's `.env` via the same `prompt_if_unset`/
      `prompt_choice_if_unset` helpers) rather than relying on
      `install.sh` to gather it first - `install.sh` just calls it
      unconditionally and only prompts for what it itself needs
      (`DATA_DIR`, ports).
    - `apps/wikimed/scripts/download-zim.sh` downloads one or more
      selectable ZIM files (via `prompt_multi_choice_if_unset` - a
      toggleable checklist) into stable, per-item filenames
      (`data/zims/<key>.zim`) with the same temp-file-then-atomic-move
      pattern, so each item's completion is independently tracked by
      "does its final file exist" - re-running only fetches what's
      still missing, e.g. after adding a new key to `WIKIMED_ZIMS`.

  `apps/_template/install.sh` has a working skeleton to copy from -
  `make add-app` scaffolds it automatically with the id/port
  substituted in.
- **uninstall.sh**: every app must also ship an `uninstall.sh` (called
  by `make uninstall`'s wizard, and directly runnable per-app).
  Contract:
  - `source` `apps/cli/scripts/lib/common.sh`, `check_deps` at the top
  - accept `--yes` (skip confirmation), `--keep-data`, `--keep-backups`,
    and `--with-images` flags (see `apps/_template/uninstall.sh`)
  - confirm before doing anything destructive, unless `--yes`
  - `podman-compose -f docker-compose.yml down -v` (add `--rmi all` if
    `--with-images`) to stop and remove containers + any named volumes
  - remove the app's data directory (resolve it via
    `_data_dir_for <app-id>`, respecting `DATA_DIR`) unless `--keep-data`
  - remove `backups/<app-id>/` unless `--keep-backups`
  - remove the app's `.env` and `.install-steps`
  - call `unmark_installed <app-id>` at the end
  - must be safe to re-run (no-op on anything already gone)

  `apps/_template/uninstall.sh` has a working skeleton to copy from -
  `make add-app` scaffolds it automatically too.
- **up.sh**: every app must also ship an `up.sh`, directly runnable
  per-app (there's no general-purpose `make up`/root wrapper - start
  apps individually). Contract:
  - `source` `apps/cli/scripts/lib/common.sh`
  - `ensure_env_file "$APP_DIR"` (copies `.env.example` -> `.env` on
    first run if missing)
  - `podman-compose -f docker-compose.yml up -d`
  - argumentless - no flags to parse
  - must be safe to re-run (idempotent)

  `apps/_template/up.sh` has a working skeleton to copy from - `make
  add-app` scaffolds it automatically too.
- **down.sh**: every app must also ship a `down.sh`, directly runnable
  per-app. Contract:
  - `podman-compose -f docker-compose.yml down`
  - argumentless - no flags to parse
  - must be safe to re-run (no-op if already stopped)

  `apps/_template/down.sh` has a working skeleton to copy from - `make
  add-app` scaffolds it automatically too.

## Registering it

Nothing to register centrally - just document the port(s) in your app's
own README. There's no shared landing page or proxy config to update.
The only thing that makes an app appear on `apps/dashboard` is shipping
a `manifest.json` (see above) - no separate registration step.

## Starting/stopping

Each app is started/stopped individually, directly via its own scripts:

```sh
./apps/my-tool/up.sh
./apps/my-tool/down.sh
```

Or run its interactive installer directly (also invoked by the root
wizard, `make install`):

```sh
./apps/my-tool/install.sh
```

## Testing your app

Before considering an app (or a change to one) done, verify it
actually works - don't just trust that `podman-compose up -d` exited 0.
A container can report success on `up -d` and then immediately crash
loop or exit clean while still being completely non-functional:

1. **Validate the compose file**:
   ```sh
   podman-compose -f apps/my-tool/docker-compose.yml config
   ```
   Catches YAML/interpolation mistakes before anything even starts.
2. **Start it and check it's actually still running** a few seconds
   later, not just that the initial command succeeded:
   ```sh
   podman-compose -f apps/my-tool/docker-compose.yml up -d
   sleep 5
   podman ps -a --filter "label=io.podman.compose.project=my-tool"
   ```
   Every container should show `Up`, not `Exited` (even `Exited (0)` -
   a clean exit code doesn't mean the service is working, just that it
   didn't crash loudly).
3. **Check the logs** for each service, especially the first few lines
   right after start - this is where entrypoint scripts print the
   actual command they ended up running:
   ```sh
   podman logs <container-name>
   ```
   Watch out for images whose entrypoint/start script already injects
   its own CLI flags (e.g. `kiwix-serve`'s Docker image auto-adds
   `--port=$PORT` itself) - passing the same flag again in your
   `command:` can produce a duplicate-flag error that silently kills
   the container. Read the image's actual entrypoint/start script
   source (not just a `docker run` example from its README) before
   assuming which flags are safe to pass yourself.
4. **Actually hit the published port**, don't just check the process is
   up - a container can be "running" while its HTTP server isn't
   listening yet, crashed internally, or is serving an error page:
   ```sh
   curl -sS -o /dev/null -w "HTTP %{http_code}\n" http://localhost:<port>/
   ```
   For anything content-driven (serving files, a database, etc.),
   spot-check that the actual expected content comes back, not just a
   200 status.
5. **Re-run `install.sh`/`up.sh`** a second time and confirm nothing
   breaks or re-prompts for already-answered config - idempotency is
   part of the contract (see above).
6. Clean up after manual testing (`./apps/my-tool/down.sh`, or
   `./apps/my-tool/uninstall.sh --yes` if you want a full reset) so you
   don't leave stray containers/data behind.

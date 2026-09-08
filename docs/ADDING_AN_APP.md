# Adding an App

Every app lives in `apps/<app-id>/` and is a fully independent Podman
Compose project, reachable directly on its own published port(s) - no
shared proxy or network involved.

```sh
./scripts/add-app.sh my-tool 8000
```

This copies `apps/_template/` to `apps/my-tool/` and substitutes the id
and default port into the compose file, install/uninstall scripts,
`.env.example`, and README (including deriving a valid `MY_TOOL_PORT`
env var name from the id).

## Contract

- **Published port(s)**: publish your service(s) directly on the host,
  with a sensible default that's overridable via `.env` (mirroring the
  existing apps' convention, e.g. `LLM_WEBUI_PORT`, `MAPS_OSRM_PORT`):
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
  `scripts/backup.sh`/`restore.sh` - no extra config needed, as long as
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
- **.env.example**: if your app needs configuration, provide an
  `.env.example` in the app folder; `scripts/up.sh` copies it to `.env` on
  first start if missing.
- **install.sh**: every app must ship an `install.sh` (this is what
  `scripts/install.sh`'s wizard calls). Contract:
  - `source` `scripts/lib/common.sh` for shared helpers
  - `check_deps` at the top
  - `ensure_env_file "$APP_DIR"` then use `prompt_if_unset VAR "prompt text" "default" "$ENV_FILE"`
    for each required setting - it must be a no-op if the variable is
    already set, so re-running the installer never re-asks answered
    questions
  - use `confirm "question"` before any heavy/slow step (large downloads,
    long-running imports)
  - start the app's containers (`podman-compose -f docker-compose.yml up -d`)
  - call `mark_installed <app-id>` at the end so `scripts/update.sh` picks
    it up automatically
  - must be safe to re-run (idempotent)

  `apps/_template/install.sh` has a working skeleton to copy from -
  `scripts/add-app.sh` scaffolds it automatically with the id/port
  substituted in.
- **uninstall.sh**: every app must also ship an `uninstall.sh` (called
  by `scripts/uninstall.sh`'s wizard, and directly runnable per-app).
  Contract:
  - `source` `scripts/lib/common.sh`, `check_deps` at the top
  - accept `--yes` (skip confirmation), `--keep-data`, `--keep-backups`,
    and `--with-images` flags (see `apps/_template/uninstall.sh`)
  - confirm before doing anything destructive, unless `--yes`
  - `podman-compose -f docker-compose.yml down -v` (add `--rmi all` if
    `--with-images`) to stop and remove containers + any named volumes
  - remove the app's data directory (resolve it via
    `_data_dir_for <app-id>`, respecting `DATA_DIR`) unless `--keep-data`
  - remove `backups/<app-id>/` unless `--keep-backups`
  - remove the app's `.env`
  - call `unmark_installed <app-id>` at the end
  - must be safe to re-run (no-op on anything already gone)

  `apps/_template/uninstall.sh` has a working skeleton to copy from -
  `scripts/add-app.sh` scaffolds it automatically too.

## Registering it

Nothing to register centrally - just document the port(s) in your app's
own README. There's no shared landing page or proxy config to update.

## Starting/stopping

```sh
podman-compose -f apps/my-tool/docker-compose.yml up -d
podman-compose -f apps/my-tool/docker-compose.yml down
```

Or via the helper that also handles `.env` bootstrapping:

```sh
./scripts/up.sh my-tool
./scripts/down.sh my-tool
```

Or run its interactive installer directly (also invoked by the root
wizard, `./scripts/install.sh`):

```sh
./apps/my-tool/install.sh
```

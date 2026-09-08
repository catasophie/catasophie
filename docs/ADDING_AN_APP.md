# Adding an App

Every app lives in `apps/<app-id>/` and is a fully independent Podman
Compose project, reachable directly on its own published port(s) - no
shared proxy or network involved.

```sh
make add-app ARGS="my-tool 8000"
# or: ./apps/cli/scripts/add-app.sh my-tool 8000
```

This copies `apps/_template/` to `apps/my-tool/` and substitutes the id
and default port into the compose file, install/uninstall scripts,
`.env.example`, and README (including deriving a valid `MY_TOOL_PORT`
env var name from the id).

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
- **.env.example**: if your app needs configuration, provide an
  `.env.example` in the app folder; `make up` copies it to `.env` on
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
    - `apps/llm-survival/install.sh` re-validates `OPEN_WEBUI_API_KEY`
      with a live API call on every run (not just "is it non-empty") and
      clears it if rejected, so a revoked/mistyped key gets re-prompted
      instead of silently blocking ingestion forever; `ingest.sh` tracks
      per-file ingestion so a re-run only uploads what's new.
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
make up ARGS="my-tool"
make down ARGS="my-tool"
```

Or run its interactive installer directly (also invoked by the root
wizard, `make install`):

```sh
./apps/my-tool/install.sh
```

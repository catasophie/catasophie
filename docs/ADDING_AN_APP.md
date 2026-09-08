# Adding an App

Every app lives in `apps/<app-id>/` and is a fully independent Podman
Compose project.

```sh
./scripts/add-app.sh my-tool /my-tool/ 8000
```

This copies `apps/_template/` to `apps/my-tool/` and substitutes the id,
URL path, and port into the compose file and README.

## Contract

- **Network**: join the shared external `catasophie` network (already
  created by `scripts/up.sh`).
- **No host ports**: don't publish ports directly to the host - only
  Traefik should be able to reach your service, over the shared network.
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
- **Traefik labels**: every routable service needs, at minimum:
  ```yaml
  labels:
    - traefik.enable=true
    - traefik.http.routers.<app-id>.rule=PathPrefix(`/<app-id>/`)
    - traefik.http.services.<app-id>.loadbalancer.server.port=<internal-port>
  ```
  If your app doesn't expect to be mounted under a path prefix, add a
  strip-prefix middleware (see `apps/_template/docker-compose.yml` for the
  pattern) so it sees requests as if it were mounted at `/`. **Stripping
  the prefix only works if the app's HTML/JS references its own assets
  with relative paths.** Many SPA frontends (Open WebUI included) hardcode
  root-relative asset paths (`/static/...`) with no configurable base
  path - stripping the prefix on the way in doesn't fix that, because the
  browser still requests `/static/...` at the domain root, missing the
  path prefix entirely. If your app does this and has no base-path env
  var, use **Host-based routing instead**:
  ```yaml
  - traefik.http.routers.<app-id>.rule=Host(`<app-id>.catasophie.local`)
  ```
  and document that users need to add `<app-id>.catasophie.local` to
  `/etc/hosts` (see `apps/llm-survival/docker-compose.yml` for a real
  example - Open WebUI required this).

  **Do not set an explicit `traefik.http.routers.<name>.priority` label**
  unless you have a specific conflict to resolve between two routers of
  equal rule length. Traefik auto-computes priority from rule
  specificity (longer/more specific `PathPrefix` naturally outranks
  shorter ones, so any `/your-app/...` route always wins over the root
  landing page's catch-all `/`). Hardcoding equal priorities on two
  routers makes Traefik's tie-break arbitrary and can cause every request
  to silently fall through to the wrong service (this happened once with
  the landing page and `offline-maps`'s web router both set to
  `priority=1` - every app path 404'd against the landing container until
  the hardcoded priorities were removed).
- **README.md**: document what the app does, how to run it, and any
  one-time setup (model downloads, data imports, etc.) - keep heavy setup
  steps as explicit scripts, not something that runs automatically.
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
  `scripts/add-app.sh` scaffolds it automatically with the id/path/port
  substituted in.

## Registering it

Add a link to `proxy/landing/index.html` so it shows up on the landing
page. Nothing else needs to change - the proxy discovers the new router
automatically once the app's container is running on the `catasophie`
network.

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

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
- **Data**: persistent data goes under `./data/` inside the app folder
  (already gitignored via the root `**/data/` pattern).
- **Traefik labels**: every routable service needs, at minimum:
  ```yaml
  labels:
    - traefik.enable=true
    - traefik.http.routers.<app-id>.rule=PathPrefix(`/<app-id>/`)
    - traefik.http.services.<app-id>.loadbalancer.server.port=<internal-port>
  ```
  If your app doesn't expect to be mounted under a path prefix, add a
  strip-prefix middleware (see `apps/_template/docker-compose.yml` for the
  pattern) so it sees requests as if it were mounted at `/`.
- **README.md**: document what the app does, how to run it, and any
  one-time setup (model downloads, data imports, etc.) - keep heavy setup
  steps as explicit scripts, not something that runs automatically.
- **.env.example**: if your app needs configuration, provide an
  `.env.example` in the app folder; `scripts/up.sh` copies it to `.env` on
  first start if missing.

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

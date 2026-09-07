# catasophie

A self-hosted, containerized "personal infrastructure box" that keeps
working when the power grid or internet is down. Runs on a Raspberry Pi,
mini PC, or laptop; optionally broadcasts its own WiFi hotspot; hosts a
growing set of offline-capable tools behind a single web dashboard.

## Status

Foundation + Ops scaffolding (dashboard, auth, reverse proxy, first-boot
wizard, backup/restore, offline updates, power monitor, health-check
"doctor" script). Tool modules (offline maps, local LLM/RAG, radio/SDR)
are planned but not yet implemented - see `docs/PLUGIN_SPEC.md` for how to
add them.

## Quick start

Requires [Podman](https://podman.io/docs/installation) and
[podman-compose](https://github.com/containers/podman-compose)
(`brew install podman-compose` or `pip install podman-compose`).

```sh
./install.sh
```

Then open `https://catasophie.local/` (or `https://<device-ip>/`) to run
the first-boot setup wizard (admin account, hardware profile, power
monitor backend, WiFi hotspot, map region). The connection uses a
locally-generated self-signed certificate (Caddy's `tls internal`) so it
works fully offline - your browser will show a one-time certificate
warning, which is expected for a self-hosted local device.

If you want this device to broadcast its own WiFi hotspot:

```sh
sudo ./scripts/setup-wifi-ap.sh
```

## Everyday operations

| Task | Command |
|---|---|
| Check that everything is configured/working correctly | `./scripts/doctor.sh` (or `--json`) |
| Back up config + tool data | `./scripts/backup.sh [destination]` |
| Restore from a backup | `./scripts/restore.sh <archive.tar.gz>` |
| Apply an offline ("sneakernet") update | drop files into `updates/incoming/`, then `./scripts/apply-update.sh` |
| Reset the admin password | `./scripts/generate-admin-password.sh` |

## Repository layout

```
catasophie/
├── compose.yaml              # core services (proxy, auth, dashboard)
├── install.sh                # installer entrypoint
├── scripts/                  # ops scripts (doctor, backup, restore, wifi, updates)
├── core/
│   ├── dashboard/             # FastAPI + HTMX dashboard app
│   ├── proxy/                 # Caddy reverse proxy config
│   └── auth/                  # Authelia (multi-user auth) config
├── tools/
│   └── _template/              # copy this to scaffold a new tool
├── updates/
│   ├── incoming/               # drop offline update files here
│   └── applied/                 # processed updates are moved here
└── docs/
    ├── ARCHITECTURE.md
    ├── PLUGIN_SPEC.md          # tool manifest contract
    └── HARDWARE.md
```

## Adding a new tool

See `docs/PLUGIN_SPEC.md`. In short: copy `tools/_template/`, fill in
`manifest.json` and `docker-compose.yml`, optionally add a
`healthcheck.sh`. The dashboard discovers it automatically - no core code
changes required.

## Design docs

- `docs/ARCHITECTURE.md` - request flow, auth model, lazy-start design
- `docs/HARDWARE.md` - Pi/mini-PC/laptop profiles, power monitor backends,
  storage guidance
- `docs/PLUGIN_SPEC.md` - tool manifest schema and conventions

# Plugin / Tool Spec

Every tool lives in `tools/<tool-name>/` and consists of:

```
tools/<tool-name>/
├── manifest.json        # required
├── docker-compose.yml    # required
├── healthcheck.sh        # optional, used by `scripts/doctor.sh`
└── data/                 # optional, gitignored, persistent volume data
```

## manifest.json schema

```jsonc
{
  "id": "maps",                     // unique, matches folder name
  "name": "Offline Maps",           // display name
  "description": "Offline navigation, routing and POI search",
  "icon": "map",                    // icon key used by dashboard (lucide icon name)
  "category": "information",        // information | communication | system
  "url_path": "/tools/maps/",       // path the reverse proxy routes to this tool
  "port": 8081,                     // internal container port the tool listens on
  "health_check": "/health",        // path (relative to url_path) dashboard/proxy pings
  "autostart": false,               // if true, tool starts with `podman-compose up`
                                     // if false, dashboard starts it on-demand (lazy-start)
  "required_role": "user",          // "user" | "admin" - who is allowed to access this tool
  "requires_host_device": [],       // e.g. ["/dev/ttyUSB0"] - device paths that must be
                                     // passed through into the container (USB/serial/etc.)
  "version": "0.1.0"
}
```

### Field notes

- **autostart**: heavy tools (LLM, maps, radio) should default to `false` on constrained
  hardware (Raspberry Pi) so the box doesn't try to run everything simultaneously.
  The dashboard's tool-control panel lets a user start/stop tools on demand.
- **required_role**: enforced by the reverse proxy via Authelia forward-auth. `admin`
  should be used for anything touching system config, backups, or updates.
- **requires_host_device**: any tool needing direct hardware access (USB SDR dongle,
  serial Meshtastic-style device, etc.) must declare the device paths here so the
  installer can generate the right udev rules / compose `devices:` entries, and so
  `doctor.sh` can verify the device is present and accessible.

## docker-compose.yml conventions

- Use the tool's `id` as the compose service name prefix (e.g. `maps-tiles`, `maps-router`).
- Persistent data goes under `./data/` (relative to the tool folder), which is gitignored.
- Tools should NOT publish ports directly to the host; they should only be reachable
  through the shared Podman network so the reverse proxy is the single entry point.
- Join the shared external network defined in the top-level `compose.yaml`
  (network name: `catasophie`).

## healthcheck.sh conventions

Optional script, executable, no arguments. Contract:

- Exit code `0` = healthy, non-zero = unhealthy.
- Print exactly one line of human-readable status to stdout.
- Should run fast (< 5s) and not require credentials beyond what's available on
  the local Podman network.

`scripts/doctor.sh` auto-discovers and runs every `tools/*/healthcheck.sh` it finds.

## Adding a new tool

1. Copy `tools/_template/` to `tools/<your-tool>/`.
2. Fill in `manifest.json`.
3. Write `docker-compose.yml` joining the `catasophie` network.
4. (Optional) write `healthcheck.sh`.
5. Restart the dashboard (or wait for its manifest refresh) — it will pick up the
   new tool automatically. No dashboard code changes required.

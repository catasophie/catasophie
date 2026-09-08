# __APP_ID__

Copy of `apps/_template/` - describe what this app does here.

## Run

```sh
podman-compose -f apps/__APP_ID__/docker-compose.yml up -d
```

Then visit `http://localhost:__PORT__/` (or whatever you set
`__PORT_VAR__` to - also reachable at `http://<device-ip>:__PORT__/`
from another device on the LAN).

## Data

Persistent data lives in `./data/` (gitignored), or wherever `DATA_DIR`
in `.env` points (e.g. an external drive) - see `install.sh`.

# apps/external/ - third-party apps

This folder is where **you** add third-party/community apps that aren't
maintained in this repo - as opposed to `apps/<id>/`, which is only for
apps shipped with catasophie itself. Everything under here is
gitignored (see `docs/EXTERNAL_APPS.md` for the full picture); nothing
you put here ever gets committed to this repo or touched by `git pull`/
`make update`'s "pull latest repo changes" step.

## Adding one

There is **no wizard or clone command for this** - you do it by hand,
which is the point: by manually running the clone yourself, you're
assumed to already know what you're adding and where it came from.

```sh
git clone <third-party-repo-url> apps/external/<id>
```

Requirements for `apps/external/<id>/` to be recognized:

- `docker-compose.yml` - must publish its port(s) via an env var with a
  default, e.g. `${MY_TOOL_PORT:-8000}:8000` (same convention as
  first-party apps - lets the port be checked for collisions and
  reconfigured via `.env`).
- `manifest.json` - same schema as `docs/ADDING_AN_APP.md`, plus
  `"type": "external"` and (recommended) a `"source"` field with the
  repo URL. Without this, the app won't show up on the dashboard or in
  `make install`'s picker.

Everything else - `install.sh`, `uninstall.sh`, `up.sh`, `down.sh`,
`.env.example` - is optional. If present, it's used as-is, identical to
a first-party app. If absent, a generic driver
(`apps/cli/scripts/lib/external.sh`) drives `podman-compose` directly.

## Before it can run anything

Third-party code runs arbitrary containers (and shell scripts, if it
ships any) with your user's podman privileges. Before install/update
will do anything with it, you must explicitly review it:

```sh
./apps/cli/scripts/review-external.sh <id>
```

This prints every reviewable file (compose file + any scripts) and asks
for explicit confirmation. Re-review is required again any time those
files change - including after `make update` pulls new commits into an
app you cloned as a git checkout.

See `docs/EXTERNAL_APPS.md` for the full contract, and how
install/uninstall/update/backup/restore treat these apps.

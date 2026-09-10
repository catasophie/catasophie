# Third-Party / External Apps

`apps/<id>/` (covered by `docs/ADDING_AN_APP.md`) is for apps that are
shipped and maintained *in this repo*. `apps/external/` is the
equivalent mechanism for apps **you** add yourself - things you found
online, wrote for your own use, or got from someone else - without
requiring a PR to this repo or full compliance with the first-party
contract.

See also `apps/external/README.md` for the short version.

## How it works

- `apps/external/` is gitignored entirely (except this file's sibling
  README) - nothing you put there is ever committed to this repo or
  touched by the repo's own `git pull`.
- You add an app by manually running:
  ```sh
  git clone <third-party-repo-url> apps/external/<id>
  ```
  There is **no wizard or `make` command that does this cloning for
  you** - that's deliberate. By choosing to clone something in by hand,
  you're assumed to already know what it is and where it came from.
- Once cloned, the app is addressed as the id `external/<id>` by every
  script and by the dashboard - e.g. `make install ARGS="external/<id>"`,
  `make update ARGS="external/<id>"`, `make uninstall ARGS="external/<id>"`.

## The minimum contract

Unlike first-party apps, `apps/external/<id>/` only *requires*:

- `docker-compose.yml` - and it must still publish its port(s) via an
  env var with a default (`${MY_TOOL_PORT:-8000}:8000`), same
  convention as first-party apps. This is the one rule that survives
  from the full contract - without it, port-collision checks and
  `.env`-based reconfiguration have nothing to hook into.
- `manifest.json` - same schema as `docs/ADDING_AN_APP.md`, plus two
  extra fields:
  ```json
  {
    "name": "Some Third-Party Tool",
    "description": "...",
    "category": "...",
    "icon": "server",
    "port": { "envVar": "MY_TOOL_PORT", "default": 8000 },
    "type": "external",
    "source": "https://github.com/someone/some-tool.git"
  }
  ```
  Without a manifest, the app won't show up on the dashboard or in
  `make install`'s picker (same "opt-in via manifest" rule as
  first-party apps).

Everything else is optional:

- `install.sh` / `uninstall.sh` / `up.sh` / `down.sh` - if present,
  used exactly as-is (identical to a first-party app, see
  `docs/ADDING_AN_APP.md`'s contract for each).
- `.env.example` - copied to `.env` on first run if present, same as
  first-party apps.

When any of these scripts are missing, a generic driver
(`apps/cli/scripts/lib/external.sh`) falls back to driving
`podman-compose` directly against `docker-compose.yml` (and a plain
`.env` copy/touch for config).

## Mandatory review before anything runs

Third-party content runs arbitrary containers - and arbitrary shell
code, if it ships `install.sh`/etc. - with your user's podman
privileges. Before `install`/`update` will do anything with an external
app, you must explicitly review it:

```sh
./apps/cli/scripts/review-external.sh <id>
# or: make review-external ARGS="<id>"
```

This prints every reviewable file (`docker-compose.yml` and any
`install.sh`/`uninstall.sh`/`up.sh`/`down.sh`/`.env.example`) and asks
for explicit confirmation before recording a content hash as
"reviewed". `install`/`update`/the dashboard's Start button all check
this hash and refuse to run the app if it doesn't match - including
after the files change (e.g. `make update` pulling new commits into an
app you originally reviewed at an older commit forces a re-review
before it's restarted).

The dashboard shows apps pending (re-)review as **Needs review** and
disables their Start button - the review step itself is CLI-only (it
needs to show you file contents and take an interactive yes/no), so it
can't be done by clicking a dashboard button.

## Install / uninstall / update / backup / restore

External apps participate in the same commands as first-party apps,
addressed by the `external/<id>` id:

```sh
make install ARGS="external/my-tool"
make uninstall ARGS="external/my-tool"       # stops/removes containers+volumes+data+.env - never deletes the git checkout itself
make update                                   # also updates every installed external/* app
make backup ARGS="external/my-tool"
make restore ARGS="external/my-tool"
```

- **Install**: blocked by the review gate above; otherwise runs the
  app's own `install.sh` if present, else the generic fallback
  (`ensure_data_dir` + `podman-compose up -d`).
- **Uninstall**: never deletes `apps/external/<id>/` itself (that's
  your own git checkout) - only stops/removes containers, volumes,
  data (unless `--keep-data`), `.env`, and backups (unless
  `--keep-backups`).
- **Update**: if `apps/external/<id>/.git` exists, `make update`
  `git pull`s it (fast-forward only - aborts on a dirty tree or
  diverged history rather than forcing anything), then re-checks the
  review hash. If the pull changed any reviewable file, the update
  stops there and reports the app as needing review - it will not
  silently restart an app whose code just changed underneath it. Apps
  that aren't a git checkout are skipped with a note to update them
  manually.
- **Backup/restore**: identical mechanism to first-party apps
  (`.env` + bind-mounted data dir + named volumes) - `dataDir`/`DATA_DIR`
  works the same way.

## Port collisions

First-party apps coordinate default ports by convention (see each
app's `.env.example`); external apps can't be checked ahead of time
against that list. `install` prints a warning (not a hard failure) if
an external app's configured/default port already appears in another
installed app's `.env` - check both apps' `.env` files if you see this.

## Trust reminder

There is no authentication anywhere in this repo (see
`docs/ARCHITECTURE.md`) and no sandboxing around third-party
containers/scripts beyond the review gate above, which only guarantees
*you looked at the files* - not that they're safe. Only add sources you
trust, and re-review carefully whenever `make update` flags one as
changed.

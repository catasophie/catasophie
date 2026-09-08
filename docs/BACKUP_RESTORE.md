# Backup & Restore

## What gets backed up

For each app, `make backup` captures:

- `.env` - the app's configuration
- data dir - wherever `DATA_DIR` in the app's `.env` currently points
  (`./data` next to the app if unset - e.g. an external drive mount if
  set), tarred as `data.tar.gz`. For `offline-maps`, `raw/` (the source
  `.osm.pbf` extract) is excluded by default - it's several hundred
  MB-GB and trivially re-downloadable via `apps/offline-maps/scripts/import-region.sh`, so
  it isn't worth including in every backup.
- Named Podman volumes declared in the app's `docker-compose.yml`,
  exported via `podman volume export` - one `volume__<name>.tar` file
  per volume (not currently used by any bundled app - both
  `wikimed` and `offline-maps` use `DATA_DIR`-driven bind mounts
  instead, precisely so their data can live on an external drive).

Backups are written to `backups/<app-id>/<timestamp>/` and are entirely
local/untracked (`backups/` is gitignored - these can contain secrets
like API keys in `.env`).

## Retention

By default the last **5** backups per app are kept; older ones are
deleted automatically each time `backup.sh` runs for that app. Override
with `--keep N`.

## Manual usage

```sh
make backup                             # back up every installed app
make backup ARGS="wikimed"              # just one app
make backup ARGS="offline-maps --keep 3"  # override retention

make restore ARGS="wikimed"                         # restore latest backup (asks to confirm)
make restore ARGS="wikimed 2026-09-07T20-30-00Z"     # restore a specific timestamp
make restore ARGS="offline-maps latest --yes"        # skip confirmation
```

`restore.sh` stops the app, replaces `.env`/data/volumes from the
backup, and starts it back up. It's destructive - it shows exactly what
will be overwritten and requires typing `yes` unless `--yes` is passed.

Note: `.env` is restored *before* data, so if the backed-up `.env` has a
different `DATA_DIR` than what's currently set, data is restored to the
backup's `DATA_DIR` location (e.g. if you back up with data on an
external drive, then restore on a machine without that drive attached,
either mount the same drive first or edit the backup's `.env` before
restoring).

## Automatic backup + rollback during updates

`make update` wraps every app update with:

1. **Backup** - `backup_app` before touching anything (skip with `--no-backup`, not recommended)
2. **Image snapshot** - records the currently-running image ID for each service
3. **Pull + recreate** - `podman-compose pull && up -d --force-recreate`
4. **Health check** - waits a few seconds, then checks every container in
   the app's compose project is in `running` state
5. **Rollback on failure** - if any container isn't running:
   - restores the backup taken in step 1 (`.env`, `data/`, volumes)
   - re-tags the previously-running image ID back onto the image
     reference the compose file uses
   - recreates containers again, now pinned to the old image
   - reports whether the rollback itself left the app healthy

By default, a failure doesn't stop the rest of the run - other apps
still get updated, and failures are summarized at the
end. Pass `--stop-on-failure` to abort immediately instead.

```sh
make update                          # update everything installed, with backup+rollback
make update ARGS="wikimed"            # just this app
make update ARGS="--stop-on-failure"
```

## Notes / limitations

- The health check is intentionally generic (container running state
  only) - it can't detect an app that starts fine but is functionally
  broken (e.g. a model that fails to load inside a running container).
  For anything critical, verify manually after an update.
- Image rollback relies on the old image blob still being present in
  local storage (Podman doesn't delete it on `pull`, just moves the
  tag) - if you've run `podman image prune` between backup and rollback,
  the image retag step will silently no-op and only the data/volumes
  will be restored.

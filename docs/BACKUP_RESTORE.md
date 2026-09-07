# Backup & Restore

## What gets backed up

For each app (or the core proxy stack, referred to as `_root`),
`scripts/backup.sh` captures:

- `.env` - the app's configuration
- `data/` - bind-mounted persistent data, if the app has any (tarred as
  `data.tar.gz`). For `offline-maps`, `data/raw/` (the source `.osm.pbf`
  extract) is excluded by default - it's several hundred MB-GB and
  trivially re-downloadable via `scripts/import-region.sh`, so it isn't
  worth including in every backup.
- Named Podman volumes declared in the app's `docker-compose.yml` (e.g.
  `llm-survival`'s `ollama-data`/`webui-data`), exported via `podman
  volume export` - one `volume__<name>.tar` file per volume.

Backups are written to `backups/<app-id>/<timestamp>/` and are entirely
local/untracked (`backups/` is gitignored - these can contain secrets
like API keys in `.env`).

## Retention

By default the last **5** backups per app are kept; older ones are
deleted automatically each time `backup.sh` runs for that app. Override
with `--keep N`.

## Manual usage

```sh
./scripts/backup.sh                       # back up root + every installed app
./scripts/backup.sh llm-survival           # just one app
./scripts/backup.sh --keep 3 offline-maps  # override retention

./scripts/restore.sh llm-survival                    # restore latest backup (asks to confirm)
./scripts/restore.sh llm-survival 2026-09-07T20-30-00Z  # restore a specific timestamp
./scripts/restore.sh offline-maps latest --yes        # skip confirmation
./scripts/restore.sh _root                             # restore root proxy state
```

`restore.sh` stops the app, replaces `.env`/`data/`/volumes from the
backup, and starts it back up. It's destructive - it shows exactly what
will be overwritten and requires typing `yes` unless `--yes` is passed.

## Automatic backup + rollback during updates

`scripts/update.sh` wraps every app update (and the core proxy) with:

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

By default, a failure doesn't stop the rest of the run - other
apps/the proxy still get updated, and failures are summarized at the
end. Pass `--stop-on-failure` to abort immediately instead.

```sh
./scripts/update.sh                    # update everything installed, with backup+rollback
./scripts/update.sh llm-survival        # just this app
./scripts/update.sh --stop-on-failure
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

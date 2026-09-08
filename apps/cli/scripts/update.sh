#!/usr/bin/env bash
# Updates the repo (git pull) and pulls+recreates containers for every
# installed app (or just the ones named as args). Before touching each
# app, takes a backup (`catasophie backup`) and snapshots its current
# image IDs; if the update leaves any container unhealthy, automatically
# restores the backup and re-pins the previous image, then recreates
# containers from it (full rollback).
#
# Usage:
#   catasophie update                       # update everything installed
#   catasophie update llm-survival           # update just this app
#   catasophie update --no-backup            # skip pre-update backups (not recommended)
#   catasophie update --stop-on-failure       # abort remaining updates on first failure
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"

check_deps

do_backup=1
stop_on_failure=0
targets=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-backup) do_backup=0; shift ;;
    --stop-on-failure) stop_on_failure=1; shift ;;
    *) targets+=("$1"); shift ;;
  esac
done

if [ -d .git ]; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "warn: working tree has uncommitted changes." >&2
    confirm "Continue with 'git pull' anyway?" || exit 1
  fi
  echo "Pulling latest changes..."
  git pull --ff-only
else
  echo "Not a git checkout, skipping git pull."
fi

# update_one <app-id> <compose_file>
# Backs up (if enabled), pulls + recreates, health-checks, and rolls back
# on failure. Returns 0 on success (or successful rollback message), 1 if
# the app is left broken after a failed rollback attempt.
update_one() {
  local app_id="$1" compose_file="$2"
  local backup_dir="" snapshot=""

  echo
  echo "=========================================="
  echo " Updating: ${app_id}"
  echo "=========================================="

  if [ "$do_backup" -eq 1 ]; then
    echo "Backing up ${app_id}..."
    backup_dir=$(backup_app "$app_id" "${BACKUPS_DIR}/${app_id}/pre-update-$(date -u +%Y-%m-%dT%H-%M-%SZ)")
    prune_backups "$app_id"
  else
    echo "warn: skipping backup for ${app_id} (--no-backup)" >&2
  fi

  snapshot=$(snapshot_image_ids "$app_id")

  echo "Pulling + recreating ${app_id}..."
  if ! podman-compose -f "$compose_file" pull; then
    echo "warn: pull failed for ${app_id}, containers left as-is" >&2
    return 1
  fi
  podman-compose -f "$compose_file" up -d --force-recreate

  if app_containers_healthy "$app_id"; then
    echo "${app_id}: OK"
    return 0
  fi

  echo "warn: ${app_id} unhealthy after update - rolling back..." >&2
  if [ -n "$backup_dir" ]; then
    ASSUME_YES=1 restore_app "$app_id" "$backup_dir"
  fi
  if [ -n "$snapshot" ]; then
    rollback_image_ids "$snapshot"
    podman-compose -f "$compose_file" up -d --force-recreate
  fi
  if app_containers_healthy "$app_id"; then
    echo "${app_id}: rolled back successfully"
    return 1
  else
    echo "error: ${app_id} still unhealthy after rollback - manual intervention needed" >&2
    return 1
  fi
}

failures=()

if [ "${#targets[@]}" -eq 0 ]; then
  mapfile -t targets < <(list_installed)
fi

if [ "${#targets[@]}" -eq 0 ]; then
  echo
  echo "No installed apps to update (run \`catasophie install\` first)."
else
  for id in "${targets[@]}"; do
    compose_file="apps/$id/docker-compose.yml"
    if [ ! -f "$compose_file" ]; then
      echo "warn: $compose_file not found, skipping $id" >&2
      continue
    fi
    if update_one "$id" "$compose_file"; then :; else
      failures+=("$id")
      [ "$stop_on_failure" -eq 1 ] && { echo "Stopping due to --stop-on-failure." >&2; exit 1; }
    fi
  done
fi

echo
if [ "${#failures[@]}" -eq 0 ]; then
  echo "Done - all updates succeeded."
else
  echo "Done - rolled back after failure: ${failures[*]}"
  exit 1
fi

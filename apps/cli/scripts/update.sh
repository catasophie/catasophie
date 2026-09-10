#!/usr/bin/env bash
# Updates the repo (git pull) and pulls+recreates containers for every
# installed app (or just the ones named as args). Before touching each
# app, takes a backup (`make backup`) and snapshots its current
# image IDs; if the update leaves any container unhealthy, automatically
# restores the backup and re-pins the previous image, then recreates
# containers from it (full rollback).
#
# Usage:
#   make update                                # update everything installed
#   make update ARGS="llm-survival"             # update just this app
#   make update ARGS="--no-backup"              # skip pre-update backups (not recommended)
#   make update ARGS="--stop-on-failure"        # abort remaining updates on first failure
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"
# shellcheck source=apps/cli/scripts/lib/external.sh
source "apps/cli/scripts/lib/external.sh"

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

# update_one <app-id>
# Backs up (if enabled), pulls + recreates, health-checks, and rolls back
# on failure. Returns 0 on success (or successful rollback message), 1 if
# the app is left broken after a failed rollback attempt, 2 if an
# external app pulled new commits that need review before it can be
# restarted (see apps/cli/scripts/lib/external.sh's external_update).
update_one() {
  local app_id="$1"
  local compose_file; compose_file=$(_compose_file_for "$app_id")
  local backup_dir="" snapshot=""
  local is_external=0
  [[ "$app_id" == external/* ]] && is_external=1

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

  if [ "$is_external" -eq 1 ]; then
    # external_update handles its own git pull + review gate + compose
    # pull/up - see apps/cli/scripts/lib/external.sh.
    local rc
    external_update "$app_id" && rc=0 || rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "${app_id}: needs review before it can be restarted - see message above." >&2
      return 2
    elif [ "$rc" -ne 0 ]; then
      echo "warn: update failed for ${app_id}, containers left as-is" >&2
      return 1
    fi
  else
    echo "Pulling + recreating ${app_id}..."
    if ! podman-compose -f "$compose_file" pull; then
      echo "warn: pull failed for ${app_id}, containers left as-is" >&2
      return 1
    fi
    podman-compose -f "$compose_file" up -d --force-recreate
  fi

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
needs_review=()

if [ "${#targets[@]}" -eq 0 ]; then
  mapfile -t targets < <(list_installed)
fi

if [ "${#targets[@]}" -eq 0 ]; then
  echo
  echo "No installed apps to update (run \`make install\` first)."
else
  for id in "${targets[@]}"; do
    compose_file=$(_compose_file_for "$id")
    if [ ! -f "$compose_file" ]; then
      echo "warn: $compose_file not found, skipping $id" >&2
      continue
    fi
    update_one "$id" && rc=0 || rc=$?
    if [ "$rc" -eq 2 ]; then
      needs_review+=("$id")
    elif [ "$rc" -ne 0 ]; then
      failures+=("$id")
      [ "$stop_on_failure" -eq 1 ] && { echo "Stopping due to --stop-on-failure." >&2; exit 1; }
    fi
  done
fi

echo
if [ "${#failures[@]}" -eq 0 ] && [ "${#needs_review[@]}" -eq 0 ]; then
  echo "Done - all updates succeeded."
else
  [ "${#needs_review[@]}" -gt 0 ] && echo "Needs review before restart (run ./apps/cli/scripts/review-external.sh <id>): ${needs_review[*]}"
  [ "${#failures[@]}" -gt 0 ] && echo "Done - rolled back after failure: ${failures[*]}"
  exit 1
fi

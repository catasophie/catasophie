#!/usr/bin/env bash
# Backs up app data (bind-mounted ./data + named podman volumes) and
# .env files, so it can be rolled back to via scripts/restore.sh. Used
# automatically by scripts/update.sh before each update.
#
# Usage:
#   ./scripts/backup.sh                    # backs up every installed app
#   ./scripts/backup.sh llm-survival        # just one app
#   ./scripts/backup.sh --keep 3 offline-maps
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=lib/common.sh
source "scripts/lib/common.sh"

check_deps

keep=5
targets=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep) keep="$2"; shift 2 ;;
    *) targets+=("$1"); shift ;;
  esac
done

if [ "${#targets[@]}" -eq 0 ]; then
  mapfile -t targets < <(list_installed)
fi

timestamp=$(date -u +%Y-%m-%dT%H-%M-%SZ)

for app_id in "${targets[@]}"; do
  dest_dir="${BACKUPS_DIR}/${app_id}/${timestamp}"
  echo "== Backing up: ${app_id} =="
  backup_app "$app_id" "$dest_dir" >/dev/null
  prune_backups "$app_id" "$keep"
  echo "  -> ${dest_dir}"
done

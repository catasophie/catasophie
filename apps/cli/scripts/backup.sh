#!/usr/bin/env bash
# Backs up app data (bind-mounted ./data + named podman volumes) and
# .env files, so it can be rolled back to via `make restore`. Used
# automatically by `make update` before each update.
#
# Usage:
#   make backup                                    # backs up every installed app
#   make backup ARGS="llm-survival"                 # just one app
#   make backup ARGS="offline-maps --keep 3"
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"

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

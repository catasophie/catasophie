#!/usr/bin/env bash
# Restores an app's .env, bind-mounted data/, and named volumes from a
# backup created by `make backup`. Destructive - overwrites current
# state - so it asks for confirmation unless --yes is passed.
#
# Usage:
#   make restore ARGS="<app-id> [timestamp|latest] [--yes]"
#   make restore ARGS="llm-survival"                          # restores latest
#   make restore ARGS="llm-survival 2026-09-07T20-30-00Z"
#   make restore ARGS="offline-maps latest --yes"
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"

check_deps

app_id="${1:?usage: restore.sh <app-id> [timestamp|latest] [--yes]}"
which="${2:-latest}"
ASSUME_YES=0
for arg in "$@"; do
  [ "$arg" = "--yes" ] && ASSUME_YES=1
done
[ "$which" = "--yes" ] && which="latest"
export ASSUME_YES

backup_dir=$(resolve_backup_dir "$app_id" "$which")
if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
  echo "error: no backup found for '${app_id}' (looked for '${which}' under backups/${app_id}/)" >&2
  exit 1
fi

restore_app "$app_id" "$backup_dir"
echo "Restored ${app_id} from ${backup_dir}"

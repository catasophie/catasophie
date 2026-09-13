#!/usr/bin/env bash
# Views/sets/clears the global storage directory (GLOBAL_STORAGE_DIR in
# the repo root's .env) used as the default base for every app's data -
# see README.md's "Storing data on an external drive" section. Unlike
# configure_global_storage_dir (called once from bootstrap.sh, which
# only prompts if unset), this always shows the current value and lets
# you change it any time.
#
# Usage:
#   ./apps/cli/scripts/set-storage.sh
#   make set-storage
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"

ensure_env_file "$CATASOPHIE_ROOT"

current=$(grep -E '^GLOBAL_STORAGE_DIR=' "$ROOT_ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2-)

echo "== Global storage directory =="
echo "Current: ${current:-<none - each app uses its own ./data folder>}"
echo
echo "Set to an absolute path (e.g. an external drive mount) to have"
echo "every app's installer default its DATA_DIR to <path>/<app-id>."
echo "Leave blank to clear it (apps default back to their own ./data)."
echo
echo "Note: this only changes the *default* offered to apps not yet"
echo "installed (or reinstalled after clearing their own DATA_DIR) - it"
echo "does not move any already-installed app's existing data."
echo

read -r -p "New global storage directory [${current}]: " new_val
new_val="${new_val:-$current}"

set_env_var GLOBAL_STORAGE_DIR "$new_val" "$ROOT_ENV_FILE"

if [ -n "$new_val" ]; then
  echo "GLOBAL_STORAGE_DIR set to: ${new_val}"
else
  echo "GLOBAL_STORAGE_DIR cleared."
fi

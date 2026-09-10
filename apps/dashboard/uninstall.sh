#!/usr/bin/env bash
# Uninstalls the dashboard: stops the running process, removes its .env,
# .install-steps, and PID/log files, and optionally node_modules.
# Destructive-ish (removes config); asks for confirmation unless --yes.
# Safe to re-run (no-op on anything already gone).
#
# Usage:
#   ./uninstall.sh                # prompts, then removes everything
#   ./uninstall.sh --yes          # skip confirmation
#   ./uninstall.sh --keep-deps    # keep node_modules (skip re-download on reinstall)
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

APP_ID="dashboard"

ASSUME_YES=0
KEEP_DEPS=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --keep-deps) KEEP_DEPS=1 ;;
    *) echo "warn: unknown option '$arg'" >&2 ;;
  esac
done

echo "== dashboard uninstall =="
echo "This will stop the dashboard process, disable boot autostart, and remove:"
echo "  - ${APP_DIR}/.env and .install-steps"
echo "  - ${APP_DIR}/.dashboard.pid and dashboard.log"
[ "$KEEP_DEPS" = "1" ] || echo "  - ${APP_DIR}/node_modules"

if [ "$ASSUME_YES" != "1" ]; then
  read -r -p "Type 'yes' to continue: " answer
  [ "$answer" = "yes" ] || { echo "Aborted."; exit 1; }
fi

"$BASH" "${APP_DIR}/scripts/uninstall-autostart.sh" || true
"$BASH" "${APP_DIR}/down.sh" || true

rm -f "${APP_DIR}/.env" "${APP_DIR}/.install-steps" "${APP_DIR}/.dashboard.pid" "${APP_DIR}/dashboard.log"

if [ "$KEEP_DEPS" != "1" ]; then
  rm -rf "${APP_DIR}/node_modules"
fi

unmark_installed "$APP_ID"
echo "== dashboard uninstalled =="

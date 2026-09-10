#!/usr/bin/env bash
# Removes the systemd unit installed by install-autostart.sh: stops and
# disables "catasophie-dashboard.service" and deletes the unit file.
# Idempotent - safe to re-run (no-op if the unit was never installed).
# Does not touch the dashboard's own PID/log files or .env - just the
# boot-autostart registration. Run ./apps/dashboard/down.sh separately
# if you also want to stop a currently-running dashboard process that
# wasn't started via the unit.
#
# Usage:
#   ./apps/dashboard/scripts/uninstall-autostart.sh
set -euo pipefail
UNIT_NAME="catasophie-dashboard.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl not found - nothing to remove."
  exit 0
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "error: not running as root and 'sudo' isn't available - re-run as root or install sudo." >&2
    exit 1
  fi
fi

if ! $SUDO systemctl list-unit-files "$UNIT_NAME" 2>/dev/null | grep -q "$UNIT_NAME" && [ ! -f "$UNIT_PATH" ]; then
  echo "Autostart is not installed - nothing to do."
  exit 0
fi

echo "Disabling and removing ${UNIT_NAME}..."
$SUDO systemctl disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
$SUDO rm -f "$UNIT_PATH"
$SUDO systemctl daemon-reload

echo "== dashboard autostart disabled =="

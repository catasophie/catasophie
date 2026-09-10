#!/usr/bin/env bash
# Registers a system-level systemd unit ("catasophie-dashboard.service")
# so the dashboard starts automatically on host boot, without needing
# any user to log in first (a login-based systemd --user unit would
# additionally need `loginctl enable-linger`, which this deliberately
# avoids). The unit runs the dashboard as the same non-root user that
# ran this script - never as root - via up.sh/down.sh, so its behavior
# (PID file, log file, node_modules ownership) is identical to running
# those scripts by hand.
#
# Idempotent - safe to re-run (no-op if the unit is already installed
# and enabled).
#
# Usage:
#   ./apps/dashboard/scripts/install-autostart.sh
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_NAME="catasophie-dashboard.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"
TEMPLATE_PATH="${APP_DIR}/${UNIT_NAME}.template"

if ! command -v systemctl >/dev/null 2>&1; then
  echo "error: systemctl not found - this host doesn't appear to use systemd." >&2
  echo "  Boot autostart for the dashboard requires systemd; skipping." >&2
  exit 1
fi

if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "error: missing unit template: ${TEMPLATE_PATH}" >&2
  exit 1
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

if $SUDO systemctl is-enabled "$UNIT_NAME" >/dev/null 2>&1; then
  echo "Autostart already enabled (${UNIT_NAME})."
  $SUDO systemctl is-active "$UNIT_NAME" >/dev/null 2>&1 || $SUDO systemctl start "$UNIT_NAME"
  exit 0
fi

DASHBOARD_USER="$(id -un)"
DASHBOARD_GROUP="$(id -gn)"

# systemd system units run with a minimal default PATH
# (/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin) that
# won't include node/npm if they were installed via nvm or another
# per-user version manager rather than a system package. Resolve the
# directories actually on this shell's PATH that node/npm live in right
# now (whatever's active when this script is run) and prepend them, so
# the unit works the same way regardless of how Node was installed.
node_dir="" npm_dir=""
command -v node >/dev/null 2>&1 && node_dir="$(dirname "$(command -v node)")"
command -v npm >/dev/null 2>&1 && npm_dir="$(dirname "$(command -v npm)")"
if [ -z "$node_dir" ]; then
  echo "error: 'node' not found on PATH - install Node.js 18+ first." >&2
  exit 1
fi
DASHBOARD_PATH="${node_dir}"
if [ -n "$npm_dir" ] && [ "$npm_dir" != "$node_dir" ]; then
  DASHBOARD_PATH="${DASHBOARD_PATH}:${npm_dir}"
fi
DASHBOARD_PATH="${DASHBOARD_PATH}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "Installing ${UNIT_PATH} (runs as ${DASHBOARD_USER}:${DASHBOARD_GROUP})..."
sed \
  -e "s#__APP_DIR__#${APP_DIR}#g" \
  -e "s#__DASHBOARD_USER__#${DASHBOARD_USER}#g" \
  -e "s#__DASHBOARD_GROUP__#${DASHBOARD_GROUP}#g" \
  -e "s#__DASHBOARD_PATH__#${DASHBOARD_PATH}#g" \
  "$TEMPLATE_PATH" | $SUDO tee "$UNIT_PATH" >/dev/null

$SUDO systemctl daemon-reload
$SUDO systemctl enable --now "$UNIT_NAME"

echo "== dashboard autostart enabled =="
echo "  Check status: systemctl status ${UNIT_NAME}"
echo "  Follow logs:  journalctl -u ${UNIT_NAME} -f"
echo "  Disable:      ./apps/dashboard/scripts/uninstall-autostart.sh"

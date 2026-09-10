#!/usr/bin/env bash
# Interactive installer for the dashboard. Idempotent - safe to re-run.
#
# NOTE: the dashboard deviates from the standard app contract in
# docs/ADDING_AN_APP.md - it is NOT a podman-compose project. It's a
# plain Node/Fastify process that runs directly on the host, because it
# needs to start/stop *other* apps' containers by invoking their own
# up.sh/down.sh - see this app's README.md and docs/ARCHITECTURE.md for
# why. It still reuses common.sh's env/marker helpers, and still needs
# podman/podman-compose on PATH (to control the other apps and inspect
# their container state), so check_deps still applies.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

echo "== dashboard install =="
check_deps

if ! command -v node >/dev/null 2>&1; then
  echo "error: missing required tool: node (Node.js 18+)" >&2
  echo "  install it via your distro's package manager or https://nodejs.org/" >&2
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "error: missing required tool: npm (usually bundled with Node.js)" >&2
  exit 1
fi

ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset DASHBOARD_PORT \
  "Port to publish the dashboard on (http://localhost:<port>/)" \
  "8000" "$ENV_FILE"

echo "Installing dashboard dependencies (npm install)..."
(cd "$APP_DIR" && npm install --no-audit --no-fund)

"$BASH" "${APP_DIR}/up.sh"

if command -v systemctl >/dev/null 2>&1; then
  prompt_choice_if_unset DASHBOARD_AUTOSTART \
    "Autostart the dashboard on boot (systemd, no login required)?" \
    "yes no" "yes" "$ENV_FILE"
  if [ "${DASHBOARD_AUTOSTART}" = "yes" ]; then
    "$BASH" "${APP_DIR}/scripts/install-autostart.sh"
  else
    echo "Skipping boot autostart. Enable later with:"
    echo "  ./apps/dashboard/scripts/install-autostart.sh"
  fi
else
  echo "note: systemd not found on this host - skipping boot autostart setup."
fi

mark_installed dashboard
echo "== dashboard installed. Visit http://localhost:${DASHBOARD_PORT:-8000}/ =="

#!/usr/bin/env bash
# Starts the dashboard. Idempotent - safe to re-run (no-op if already
# running). NOT a podman-compose project - see README.md for why: this
# starts a plain Node process directly on the host, tracked via a PID
# file (.dashboard.pid), so it can shell out to other apps' own
# up.sh/down.sh to start/stop them.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

ensure_env_file "$APP_DIR"

PID_FILE="${APP_DIR}/.dashboard.pid"
LOG_FILE="${APP_DIR}/dashboard.log"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Dashboard already running (pid $(cat "$PID_FILE"))."
  exit 0
fi
rm -f "$PID_FILE"

if [ ! -d "${APP_DIR}/node_modules" ]; then
  echo "Installing dashboard dependencies (npm install)..."
  (cd "$APP_DIR" && npm install --no-audit --no-fund)
fi

echo "Starting dashboard..."
cd "$APP_DIR"
if command -v setsid >/dev/null 2>&1; then
  setsid nohup node server.js </dev/null >>"$LOG_FILE" 2>&1 &
else
  nohup node server.js </dev/null >>"$LOG_FILE" 2>&1 &
fi
echo $! > "$PID_FILE"
disown %% 2>/dev/null || true

sleep 1
if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  # shellcheck disable=SC1091
  source "${APP_DIR}/.env" 2>/dev/null || true
  echo "Dashboard started (pid $(cat "$PID_FILE")). Visit http://localhost:${DASHBOARD_PORT:-8000}/"
  echo "Logs: ${LOG_FILE}"
else
  echo "error: dashboard failed to start - check ${LOG_FILE}" >&2
  rm -f "$PID_FILE"
  exit 1
fi

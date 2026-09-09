#!/usr/bin/env bash
# Stops the dashboard. Safe to re-run (no-op if not running).
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PID_FILE="${APP_DIR}/.dashboard.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "Dashboard is not running."
  exit 0
fi

pid="$(cat "$PID_FILE")"

if ! kill -0 "$pid" 2>/dev/null; then
  echo "Dashboard is not running (stale pid file removed)."
  rm -f "$PID_FILE"
  exit 0
fi

echo "Stopping dashboard (pid ${pid})..."
kill "$pid" 2>/dev/null || true

for _ in $(seq 1 10); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.5
done

if kill -0 "$pid" 2>/dev/null; then
  echo "Dashboard didn't stop gracefully - killing it (pid ${pid})."
  kill -9 "$pid" 2>/dev/null || true
fi

rm -f "$PID_FILE"
echo "Dashboard stopped."

#!/usr/bin/env bash
# Restores a backup archive created by scripts/backup.sh.
#
# Usage: ./scripts/restore.sh <path-to-backup.tar.gz>
#
# WARNING: this overwrites .env, core/auth/users_database.yml, and every
# tool's data/ folder with the contents of the archive. Existing containers
# should be stopped first (`docker compose down`) to avoid writing to
# volumes that are actively in use.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "Usage: $0 <path-to-backup.tar.gz>" >&2
  exit 1
fi

read -rp "This will overwrite current config and tool data. Continue? [y/N] " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted."
  exit 0
fi

STAGING_DIR="$(mktemp -d)"
tar -xzf "$ARCHIVE" -C "$STAGING_DIR"

echo "==> Restoring .env..."
[ -f "$STAGING_DIR/.env" ] && cp "$STAGING_DIR/.env" .env

echo "==> Restoring auth database..."
[ -f "$STAGING_DIR/core/auth/users_database.yml" ] && \
  cp "$STAGING_DIR/core/auth/users_database.yml" core/auth/users_database.yml

echo "==> Restoring tool data..."
if [ -d "$STAGING_DIR/tools" ]; then
  for tool_dir in "$STAGING_DIR"/tools/*/; do
    tool_id="$(basename "$tool_dir")"
    if [ -d "${tool_dir}data" ]; then
      mkdir -p "tools/$tool_id"
      rm -rf "tools/$tool_id/data"
      cp -r "${tool_dir}data" "tools/$tool_id/data"
      echo "    restored tools/$tool_id/data"
    fi
  done
fi

rm -rf "$STAGING_DIR"

echo "==> Restore complete. Run 'podman-compose up -d' to bring services back up."

#!/usr/bin/env bash
# Backs up .env, auth config, and every tool's persistent ./data/ folder
# into a single timestamped archive, ideally on an external USB drive.
#
# Usage: ./scripts/backup.sh [destination-dir]
#   destination-dir defaults to ./data/backups
set -euo pipefail

cd "$(dirname "$0")/.."

DEST_DIR="${1:-data/backups}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="catasophie-backup-${TIMESTAMP}.tar.gz"
STAGING_DIR="$(mktemp -d)"

mkdir -p "$DEST_DIR"

echo "==> Staging backup contents..."
mkdir -p "$STAGING_DIR/core/auth"
[ -f .env ] && cp .env "$STAGING_DIR/.env"
[ -f core/auth/users_database.yml ] && cp core/auth/users_database.yml "$STAGING_DIR/core/auth/"

if [ -d tools ]; then
  for tool_dir in tools/*/; do
    tool_id="$(basename "$tool_dir")"
    [ "$tool_id" = "_template" ] && continue
    if [ -d "${tool_dir}data" ]; then
      mkdir -p "$STAGING_DIR/tools/$tool_id"
      cp -r "${tool_dir}data" "$STAGING_DIR/tools/$tool_id/data"
    fi
  done
fi

echo "==> Archiving to ${DEST_DIR}/${ARCHIVE_NAME}..."
tar -czf "${DEST_DIR}/${ARCHIVE_NAME}" -C "$STAGING_DIR" .

rm -rf "$STAGING_DIR"

echo "==> Backup complete: ${DEST_DIR}/${ARCHIVE_NAME}"
echo "    ($(du -h "${DEST_DIR}/${ARCHIVE_NAME}" | cut -f1))"

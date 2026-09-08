#!/usr/bin/env bash
# Uninstalls apps/llm-survival: stops + removes its containers and any
# named volumes, deletes its data directory (wherever DATA_DIR points -
# see install.sh) and backups/llm-survival/, and removes its .env.
# Destructive - asks for confirmation unless --yes is passed. Safe to
# re-run (no-op on anything already gone).
#
# Usage:
#   ./uninstall.sh                # prompts, then removes everything
#   ./uninstall.sh --yes          # skip confirmation
#   ./uninstall.sh --keep-data    # keep the data directory
#   ./uninstall.sh --keep-backups # keep backups/llm-survival/
#   ./uninstall.sh --with-images  # also remove pulled container images
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "${APP_DIR}/../../scripts/lib/common.sh"

APP_ID="llm-survival"
check_deps

ASSUME_YES=0
KEEP_DATA=0
KEEP_BACKUPS=0
WITH_IMAGES=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --keep-data) KEEP_DATA=1 ;;
    --keep-backups) KEEP_BACKUPS=1 ;;
    --with-images) WITH_IMAGES=1 ;;
    *) echo "warn: unknown option '$arg'" >&2 ;;
  esac
done

data_dir=$(_data_dir_for "$APP_ID")

echo "== ${APP_ID} uninstall =="
echo "This will stop and remove all ${APP_ID} containers/volumes,"
[ "$KEEP_DATA" = "1" ] || echo "  - delete its data directory (${data_dir})"
[ "$KEEP_BACKUPS" = "1" ] || echo "  - delete backups/${APP_ID}/"
echo "  - remove ${APP_DIR}/.env"
[ "$WITH_IMAGES" = "1" ] && echo "  - remove its pulled container images"

if [ "$ASSUME_YES" != "1" ]; then
  read -r -p "Type 'yes' to continue: " answer
  [ "$answer" = "yes" ] || { echo "Aborted."; exit 1; }
fi

if [ -f "${APP_DIR}/docker-compose.yml" ]; then
  echo "Stopping + removing containers/volumes..."
  if [ "$WITH_IMAGES" = "1" ]; then
    podman-compose -f "${APP_DIR}/docker-compose.yml" down -v --rmi all --remove-orphans || true
  else
    podman-compose -f "${APP_DIR}/docker-compose.yml" down -v --remove-orphans || true
  fi
fi

if [ "$KEEP_DATA" != "1" ] && [ -d "$data_dir" ]; then
  echo "Removing data dir: ${data_dir}"
  rm -rf "$data_dir"
fi

if [ "$KEEP_BACKUPS" != "1" ]; then
  echo "Removing backups/${APP_ID}/..."
  rm -rf "${BACKUPS_DIR}/${APP_ID}"
fi

rm -f "${APP_DIR}/.env"

unmark_installed "$APP_ID"
echo "== ${APP_ID} uninstalled =="

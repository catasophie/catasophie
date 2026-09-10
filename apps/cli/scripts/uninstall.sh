#!/usr/bin/env bash
# Uninstalls one or more apps by calling each one's own uninstall.sh
# (see docs/ADDING_AN_APP.md for the uninstall.sh contract). With no
# app-ids given, uninstalls *every app* (not just ones .installed
# happens to record - that marker can be stale, e.g. if install.sh
# crashed before reaching mark_installed) plus backups/ and the
# .installed marker - restoring the repo to its state before
# make install was ever run.
#
# Destructive - asks for confirmation unless --yes is passed.
#
# Usage:
#   make uninstall                                     # everything (full reset)
#   make uninstall ARGS="llm-survival"                  # just one app
#   make uninstall ARGS="llm-survival offline-maps"
#   make uninstall ARGS="--yes"                          # skip confirmation
#   make uninstall ARGS="--keep-data"                    # keep data directories
#   make uninstall ARGS="--keep-backups"                 # keep backups/
#   make uninstall ARGS="--with-images"                  # also remove pulled images
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"
# shellcheck source=apps/cli/scripts/lib/external.sh
source "apps/cli/scripts/lib/external.sh"

check_deps

ASSUME_YES=0
KEEP_DATA=0
KEEP_BACKUPS=0
WITH_IMAGES=0
targets=()
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --keep-data) KEEP_DATA=1 ;;
    --keep-backups) KEEP_BACKUPS=1 ;;
    --with-images) WITH_IMAGES=1 ;;
    -*) echo "warn: unknown option '$arg'" >&2 ;;
    *) targets+=("$arg") ;;
  esac
done

full_uninstall=0
if [ "${#targets[@]}" -eq 0 ]; then
  full_uninstall=1
  # Target every app that has an uninstall.sh (not just ones recorded
  # in .installed) - that marker can be stale/incomplete (e.g. an
  # install.sh that crashed partway, before reaching mark_installed, as
  # happened here), and a "remove everything" pass should be thorough
  # regardless of it. Also targets every apps/external/<id> that meets
  # the minimum contract (manifest.json + docker-compose.yml), whether
  # or not it ships its own uninstall.sh.
  mapfile -t targets < <(list_available_apps | sort)
  mapfile -t external_targets < <(list_external_apps | sort)
  targets+=("${external_targets[@]}")
fi

echo "== make uninstall =="
if [ "${#targets[@]}" -eq 0 ]; then
  echo "No apps found under apps/."
else
  echo "This will stop and remove all containers/volumes for: ${targets[*]}"
fi
if [ "$full_uninstall" -eq 1 ]; then
  [ "$KEEP_BACKUPS" = "1" ] || echo "  - remove backups/ entirely"
  echo "  - remove the .installed marker"
fi
[ "$KEEP_DATA" = "1" ] && echo "(--keep-data: app data directories will be preserved)"
[ "$KEEP_BACKUPS" = "1" ] && echo "(--keep-backups: backups will be preserved)"

if [ "$ASSUME_YES" != "1" ]; then
  read -r -p "Type 'yes' to continue: " answer
  [ "$answer" = "yes" ] || { echo "Aborted."; exit 1; }
fi

flags=(--yes)
[ "$KEEP_DATA" = "1" ] && flags+=(--keep-data)
[ "$KEEP_BACKUPS" = "1" ] && flags+=(--keep-backups)
[ "$WITH_IMAGES" = "1" ] && flags+=(--with-images)

for id in "${targets[@]}"; do
  [ -z "$id" ] && continue
  echo
  echo "=========================================="
  echo " Uninstalling: ${id}"
  echo "=========================================="
  if [[ "$id" == external/* ]]; then
    external_uninstall "$id" "${flags[@]}"
  elif [ -x "apps/${id}/uninstall.sh" ]; then
    "apps/${id}/uninstall.sh" "${flags[@]}"
  else
    echo "warn: apps/${id}/uninstall.sh not found, skipping" >&2
  fi
done

if [ "$full_uninstall" -eq 1 ]; then
  if [ "$KEEP_BACKUPS" != "1" ]; then
    echo
    echo "Removing backups/..."
    rm -rf backups
  fi

  rm -f .installed
fi

echo
echo "== Uninstall complete =="

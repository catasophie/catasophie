#!/usr/bin/env bash
# Ingests offline ("sneakernet") updates dropped into updates/incoming/.
#
# Supported file naming conventions (drop matching files into updates/incoming/):
#   map-region-<name>.tar.gz       -> extracted into tools/maps/data/regions/<name>/
#   knowledge-corpus-<name>.zim    -> copied into tools/llm-knowledge/data/corpus/
#   tool-<id>.tar.gz                -> a full new/updated tool package, extracted
#                                      into tools/<id>/ (must contain manifest.json)
#
# Usage: ./scripts/apply-update.sh
# Processed files are moved to updates/applied/<timestamp>-<original-name>
# so re-running is safe (already-applied files won't be reprocessed).
set -euo pipefail

cd "$(dirname "$0")/.."

INCOMING_DIR="updates/incoming"
APPLIED_DIR="updates/applied"
mkdir -p "$INCOMING_DIR" "$APPLIED_DIR"

shopt -s nullglob
FILES=("$INCOMING_DIR"/*)
shopt -u nullglob

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No update files found in ${INCOMING_DIR}/"
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
APPLIED_COUNT=0
FAILED_COUNT=0

for file in "${FILES[@]}"; do
  [ -f "$file" ] || continue
  basename_file="$(basename "$file")"
  [ "$basename_file" = ".gitkeep" ] && continue

  echo "==> Processing ${basename_file}..."
  status="skipped (unrecognized naming convention)"

  if [[ "$basename_file" =~ ^map-region-(.+)\.tar\.gz$ ]]; then
    region="${BASH_REMATCH[1]}"
    target="tools/maps/data/regions/${region}"
    mkdir -p "$target"
    if tar -xzf "$file" -C "$target"; then
      status="OK: extracted map region '${region}' into ${target}"
    else
      status="FAILED: could not extract archive"
    fi

  elif [[ "$basename_file" =~ ^knowledge-corpus-(.+)\.zim$ ]]; then
    mkdir -p tools/llm-knowledge/data/corpus
    if cp "$file" tools/llm-knowledge/data/corpus/; then
      status="OK: copied knowledge corpus '${basename_file}' into tools/llm-knowledge/data/corpus/"
    else
      status="FAILED: could not copy file"
    fi

  elif [[ "$basename_file" =~ ^tool-(.+)\.tar\.gz$ ]]; then
    tool_id="${BASH_REMATCH[1]}"
    target="tools/${tool_id}"
    tmp_extract="$(mktemp -d)"
    if tar -xzf "$file" -C "$tmp_extract" && [ -f "$tmp_extract/manifest.json" ]; then
      mkdir -p "$target"
      cp -r "$tmp_extract"/. "$target"/
      status="OK: installed/updated tool '${tool_id}' in ${target}"
    else
      status="FAILED: archive did not contain a valid manifest.json at its root"
    fi
    rm -rf "$tmp_extract"
  fi

  echo "    ${status}"
  if [[ "$status" == OK:* ]]; then
    mv "$file" "${APPLIED_DIR}/${TIMESTAMP}-${basename_file}"
    APPLIED_COUNT=$((APPLIED_COUNT + 1))
  else
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

echo ""
echo "==> Done. Applied: ${APPLIED_COUNT}, Failed/Skipped: ${FAILED_COUNT}"
if [ "$APPLIED_COUNT" -gt 0 ]; then
  echo "    New/updated tools may need: podman-compose up -d"
fi

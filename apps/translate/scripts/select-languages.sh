#!/usr/bin/env bash
# Selects (or changes) which languages translate loads, and downloads
# the corresponding Argos Translate models. This is the heavy, one-time
# (or per-language-change) setup step - some languages are ~150-200MB,
# more for larger ones - see docs/ADDING_AN_APP.md.
#
# Self-contained/idempotent: safe to run directly (without install.sh)
# on a fresh checkout, and safe to re-run any time later to add/remove
# languages - unlike apps/wikimed's scripts/download-zim.sh this can't
# use prompt_multi_choice_if_unset as-is (that helper skips entirely
# once the var is set, but here we specifically want to re-prompt with
# the current selection pre-checked so it stays useful for later
# changes too). If TRANSLATE_LANGS is already exported in the process
# environment, it's used as-is and the prompt is skipped (non-interactive
# form), e.g.:
#
#   TRANSLATE_LANGS=en,es,fr,de ./scripts/select-languages.sh
#
# TRANSLATE_LANGS is a comma-separated list of ISO codes (this is also
# exactly the format LibreTranslate's LT_LOAD_ONLY expects - see
# ../docker-compose.yml). LibreTranslate installs every translation pair
# among the selected set. See https://libretranslate.com/languages for
# the current full list of valid codes - any valid code works even if
# not offered below (set TRANSLATE_LANGS directly to use one).
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset TRANSLATE_PORT \
  "Port to publish translate on (http://localhost:<port>/)" \
  "3030" "$ENV_FILE"

# A commonly-useful subset of LibreTranslate's supported languages -
# not exhaustive. Add any other valid code by setting TRANSLATE_LANGS
# directly (in .env or via the environment) instead of using the picker.
CATALOG="en es fr de ar zh hi it ja pl pt ru tr uk vi ko nl el he fa sv"

current_csv=$(grep -E '^TRANSLATE_LANGS=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
[ -z "$current_csv" ] && current_csv="en,es"
current_selection="${current_csv//,/ }"

if [ -n "${TRANSLATE_LANGS:-}" ]; then
  # Already exported (e.g. non-interactive invocation) - use as-is,
  # skip the interactive picker entirely.
  new_selection="${TRANSLATE_LANGS//,/ }"
else
  echo "Current languages: ${current_csv}"

  is_current() {
    local needle="$1" c
    for c in $current_selection; do [ "$c" = "$needle" ] && return 0; done
    return 1
  }

  new_selection=""
  tool=""
  if command -v whiptail >/dev/null 2>&1; then
    tool=whiptail
  elif command -v dialog >/dev/null 2>&1; then
    tool=dialog
  fi

  if [ -n "$tool" ]; then
    catalog_count=$(echo "$CATALOG" | wc -w)
    args=(--checklist "Which language(s) should translate load? (space to toggle, enter to confirm)" 20 78 "$catalog_count")
    for opt in $CATALOG; do
      status="OFF"
      is_current "$opt" && status="ON"
      args+=("$opt" "$opt" "$status")
    done
    if raw=$("$tool" "${args[@]}" 3>&1 1>&2 2>&3); then
      new_selection=$(echo "$raw" | tr -d '"')
    else
      echo "Cancelled - keeping current selection: ${current_csv}"
      new_selection="$current_selection"
    fi
  else
    echo "Which language(s) should translate load? (space to toggle, enter to confirm - see https://libretranslate.com/languages for the full list)"
    i=1
    declare -A idx_to_opt
    for opt in $CATALOG; do
      marker=""
      is_current "$opt" && marker=" (current)"
      printf "  %d) %s%s\n" "$i" "$opt" "$marker"
      idx_to_opt[$i]="$opt"
      i=$((i + 1))
    done
    read -r -p "Enter number(s), comma/space-separated [${current_csv}]: " answer
    if [ -z "$answer" ]; then
      new_selection="$current_selection"
    else
      picked=()
      for num in ${answer//,/ }; do
        [ -n "${idx_to_opt[$num]:-}" ] && picked+=("${idx_to_opt[$num]}")
      done
      if [ "${#picked[@]}" -eq 0 ]; then
        new_selection="$current_selection"
      else
        new_selection="${picked[*]}"
      fi
    fi
  fi
fi

# Normalize to sorted, comma-separated for stable comparison/storage.
new_csv=$(echo "$new_selection" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ',' | sed 's/,$//')
: "${new_csv:?no languages selected}"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1
podman unshare chown -R 1032:1032 "$data_dir"

if [ "$new_csv" = "$current_csv" ] && step_done translate "languages:${new_csv}"; then
  echo "No change - translate already serving: ${new_csv}"
  echo "Starting translate (in case it isn't running)..."
  podman-compose -f "${APP_DIR}/docker-compose.yml" up -d
  exit 0
fi

set_env_var TRANSLATE_LANGS "$new_csv" "$ENV_FILE"

if ! confirm "Download/update models for: ${new_csv}? (needs internet access now, can take a while - roughly 150-200MB per language)" "y"; then
  echo "Skipping download - re-run ${APP_DIR}/scripts/select-languages.sh when ready."
  exit 0
fi

echo "Starting translate with model update enabled for: ${new_csv}..."
port="${TRANSLATE_PORT:-3030}"
LT_UPDATE_MODELS=true podman-compose -f "${APP_DIR}/docker-compose.yml" up -d --force-recreate

echo "Waiting for models to finish downloading/loading (this can take several minutes)..."
deadline=$((SECONDS + 1800))
ready=0
while [ "$SECONDS" -lt "$deadline" ]; do
  langs_json=$(curl -fsS "http://localhost:${port}/languages" 2>/dev/null || true)
  if [ -n "$langs_json" ]; then
    missing=0
    for code in $new_selection; do
      echo "$langs_json" | grep -q "\"code\":\"${code}\"" || missing=1
    done
    if [ "$missing" -eq 0 ]; then
      ready=1
      break
    fi
  fi
  sleep 5
done

if [ "$ready" -ne 1 ]; then
  echo "error: timed out waiting for models - check logs with: podman logs \$(podman-compose -f ${APP_DIR}/docker-compose.yml ps -q translate)" >&2
  exit 1
fi

echo "Models ready. Recreating translate without the one-time model-update flag (so future restarts stay fully offline)..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d --force-recreate

mark_step_done translate "languages:${new_csv}"
echo "Done. translate is serving languages: ${new_csv}"

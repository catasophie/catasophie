#!/usr/bin/env bash
# Interactive installer for translate (offline machine translation via
# LibreTranslate/Argos Translate). Idempotent - safe to re-run.
#
# Language selection (TRANSLATE_LANGS) is entirely owned by
# scripts/select-languages.sh, which prompts for it (and downloads the
# corresponding models) itself, so it's self-contained whether invoked
# from here or run directly later to add/remove languages. This script
# only prompts for what it itself needs to start the container.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

echo "== translate install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset DATA_DIR \
  "Directory for persistent data - downloaded language models (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

prompt_if_unset TRANSLATE_PORT \
  "Port to publish translate on (http://localhost:<port>/)" \
  "3030" "$ENV_FILE"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1

# The LibreTranslate image runs as a fixed non-root uid (1032) - the
# bind-mounted data dir must be owned by that uid or the container fails
# to start (verified during development: plain bind mounts otherwise hit
# a PermissionError). Safe/idempotent to re-run.
podman unshare chown -R 1032:1032 "$data_dir"

"${APP_DIR}/scripts/select-languages.sh"

mark_installed translate
echo "== translate installed. Visit http://localhost:${TRANSLATE_PORT:-3030}/ =="

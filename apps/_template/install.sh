#!/usr/bin/env bash
# Interactive installer for __APP_ID__. Idempotent - safe to re-run.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

echo "== __APP_ID__ install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

# Example - replace with your app's actual required configuration:
# prompt_if_unset SOME_SETTING "Describe what this is for" "default-value" "$ENV_FILE"

prompt_if_unset DATA_DIR \
  "Directory for persistent data (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

prompt_if_unset __PORT_VAR__ \
  "Port to publish __APP_ID__ on (http://localhost:<port>/)" \
  "__PORT__" "$ENV_FILE"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1

echo "Starting __APP_ID__..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

# Example - for any heavy/fallible/multi-stage step that isn't simply
# re-running the whole thing when repeated, track its completion with
# mark_step_done/step_done so a re-run resumes instead of redoing or
# silently skipping (see docs/ADDING_AN_APP.md and
# apps/offline-maps/scripts/import-region.sh for a real example):
#
# if step_done __APP_ID__ "some-heavy-step"; then
#   echo "some-heavy-step already done - skipping"
# else
#   # ... do the heavy/fallible thing ...
#   mark_step_done __APP_ID__ "some-heavy-step"
# fi

mark_installed __APP_ID__
echo "== __APP_ID__ installed. Visit http://localhost:${__PORT_VAR__:-__PORT__}/ =="

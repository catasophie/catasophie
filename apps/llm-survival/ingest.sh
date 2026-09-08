#!/usr/bin/env bash
# Ingests the fetched corpus (corpus/data/raw/*.pdf) into an Open WebUI
# "Survival & Medical" knowledge collection via its REST API, so the LLM
# can retrieve and cite them. Tracks which files have already been added
# (via mark_step_done) so a re-run - after a partial failure, or simply
# to pick up newly-added PDFs - only uploads what's new, instead of
# re-uploading everything as duplicates.
#
# Requires: Open WebUI running and reachable, an admin account created
# via the web UI on first visit, and an API key generated from
# Settings -> Account -> API Keys.
#
# Usage:
#   OPEN_WEBUI_URL=http://localhost:3001 \
#   OPEN_WEBUI_API_KEY=sk-... \
#   ./ingest.sh
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_DIR"
# shellcheck source=../../scripts/lib/common.sh
source "${APP_DIR}/../../scripts/lib/common.sh"
APP_ID="llm-survival"

: "${OPEN_WEBUI_URL:?set OPEN_WEBUI_URL, e.g. http://localhost:3001}"
: "${OPEN_WEBUI_API_KEY:?set OPEN_WEBUI_API_KEY (Settings -> Account -> API Keys in Open WebUI)}"

KB_NAME="Survival & Medical"
auth=(-H "Authorization: Bearer ${OPEN_WEBUI_API_KEY}")

# Wraps a curl call to Open WebUI's API: splits off the HTTP status code
# (appended via -w), and on any 4xx/5xx prints the response body plus an
# actionable hint instead of leaving curl's raw failure (or a downstream
# JSON-parse traceback) as the only clue, then returns 1. Prints the
# response body to stdout on success, same as a plain curl call would.
# NOTE: since this runs via command substitution (a subshell), it can't
# `exit` the whole script directly - callers must check its exit status
# themselves, e.g. `x=$(api_call ...) || exit 1`.
# Usage: api_call <curl-args...> <url>
api_call() {
  local response status body
  if ! response=$(curl -sS -w '\n%{http_code}' "$@"); then
    echo "error: request failed (network error?) - is Open WebUI reachable at ${OPEN_WEBUI_URL}?" >&2
    return 1
  fi
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [ "$status" -ge 400 ]; then
    echo "error: request to Open WebUI failed (HTTP ${status})" >&2
    echo "  response: ${body}" >&2
    case "$status" in
      401|403|404)
        echo "  this usually means OPEN_WEBUI_API_KEY is invalid, expired, or was" >&2
        echo "  revoked - generate a new one in Open WebUI: Settings -> Account ->" >&2
        echo "  API Keys, then re-run with the new key." >&2
        ;;
    esac
    return 1
  fi
  printf '%s' "$body"
}

echo "Looking up (or creating) knowledge collection '${KB_NAME}'..."
kb_list=$(api_call "${auth[@]}" "${OPEN_WEBUI_URL}/api/v1/knowledge/list") || exit 1
kb_id=$(printf '%s' "$kb_list" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); m=[k for k in d if k.get('name')=='${KB_NAME}']; print(m[0]['id'] if m else '')")

if [ -z "$kb_id" ]; then
  kb_create=$(api_call "${auth[@]}" -H "Content-Type: application/json" \
    -X POST "${OPEN_WEBUI_URL}/api/v1/knowledge/create" \
    -d "{\"name\": \"${KB_NAME}\", \"description\": \"Curated offline survival & medical reference corpus\"}") || exit 1
  kb_id=$(printf '%s' "$kb_create" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "Created knowledge collection: $kb_id"
else
  echo "Found existing knowledge collection: $kb_id"
fi

shopt -s nullglob
for f in data/raw/*.pdf; do
  fname="$(basename "$f")"
  if step_done "$APP_ID" "ingested:${fname}"; then
    echo "skip (already ingested): ${fname}"
    continue
  fi
  echo "Uploading ${fname}..."
  file_upload=$(api_call "${auth[@]}" -F "file=@${f}" "${OPEN_WEBUI_URL}/api/v1/files/") || exit 1
  file_id=$(printf '%s' "$file_upload" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  api_call "${auth[@]}" -H "Content-Type: application/json" \
    -X POST "${OPEN_WEBUI_URL}/api/v1/knowledge/${kb_id}/file/add" \
    -d "{\"file_id\": \"${file_id}\"}" >/dev/null || exit 1
  mark_step_done "$APP_ID" "ingested:${fname}"
  echo "  added (file_id=${file_id})"
done

echo "Done. In Open WebUI, select the '${KB_NAME}' knowledge collection as a" \
     "context source (# reference or Workspace -> Knowledge) when chatting."

#!/usr/bin/env bash
# Ingests the fetched corpus (corpus/data/raw/*.pdf) into an Open WebUI
# "Survival & Medical" knowledge collection via its REST API, so the LLM
# can retrieve and cite them.
#
# Requires: Open WebUI running and reachable, an admin account created
# via the web UI on first visit, and an API key generated from
# Settings -> Account -> API Keys.
#
# webui is routed by Host (not PathPrefix - see docker-compose.yml), so
# OPEN_WEBUI_URL should point at the proxy and OPEN_WEBUI_HOST_HEADER
# supplies the Host header, unless you've added llm.catasophie.local to
# /etc/hosts and can use it directly as OPEN_WEBUI_URL instead.
#
# Usage:
#   OPEN_WEBUI_URL=http://llm.catasophie.local:8080 \
#   OPEN_WEBUI_API_KEY=sk-... \
#   ./ingest.sh
#
#   # or, without /etc/hosts configured:
#   OPEN_WEBUI_URL=http://localhost:8080 \
#   OPEN_WEBUI_HOST_HEADER=llm.catasophie.local \
#   OPEN_WEBUI_API_KEY=sk-... \
#   ./ingest.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

: "${OPEN_WEBUI_URL:?set OPEN_WEBUI_URL, e.g. http://llm.catasophie.local:8080}"
: "${OPEN_WEBUI_API_KEY:?set OPEN_WEBUI_API_KEY (Settings -> Account -> API Keys in Open WebUI)}"

KB_NAME="Survival & Medical"
auth=(-H "Authorization: Bearer ${OPEN_WEBUI_API_KEY}")
if [ -n "${OPEN_WEBUI_HOST_HEADER:-}" ]; then
  auth+=(-H "Host: ${OPEN_WEBUI_HOST_HEADER}")
fi

echo "Looking up (or creating) knowledge collection '${KB_NAME}'..."
kb_id=$(curl -fsS "${auth[@]}" "${OPEN_WEBUI_URL}/api/v1/knowledge/list" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); m=[k for k in d if k.get('name')=='${KB_NAME}']; print(m[0]['id'] if m else '')")

if [ -z "$kb_id" ]; then
  kb_id=$(curl -fsS "${auth[@]}" -H "Content-Type: application/json" \
    -X POST "${OPEN_WEBUI_URL}/api/v1/knowledge/create" \
    -d "{\"name\": \"${KB_NAME}\", \"description\": \"Curated offline survival & medical reference corpus\"}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "Created knowledge collection: $kb_id"
else
  echo "Found existing knowledge collection: $kb_id"
fi

shopt -s nullglob
for f in data/raw/*.pdf; do
  echo "Uploading $(basename "$f")..."
  file_id=$(curl -fsS "${auth[@]}" -F "file=@${f}" "${OPEN_WEBUI_URL}/api/v1/files/" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  curl -fsS "${auth[@]}" -H "Content-Type: application/json" \
    -X POST "${OPEN_WEBUI_URL}/api/v1/knowledge/${kb_id}/file/add" \
    -d "{\"file_id\": \"${file_id}\"}" >/dev/null
  echo "  added (file_id=${file_id})"
done

echo "Done. In Open WebUI, select the '${KB_NAME}' knowledge collection as a" \
     "context source (# reference or Workspace -> Knowledge) when chatting."

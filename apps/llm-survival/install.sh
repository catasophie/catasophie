#!/usr/bin/env bash
# Interactive installer for apps/llm-survival. Idempotent - safe to re-run
# (already-set config is not re-prompted, already-fetched files are
# skipped by corpus/fetch.sh).
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "${APP_DIR}/../../scripts/lib/common.sh"

echo "== llm-survival install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset OLLAMA_MODEL \
  "Ollama model tag (small: phi3:mini/llama3.2:3b, bigger: llama3.1:8b/gemma2:9b)" \
  "llama3.2:3b" "$ENV_FILE"

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# kiwix-serve needs a valid library.xml to start at all; seed an empty one
# so it comes up cleanly (serving zero books) instead of crash-looping
# until corpus/fetch.sh adds a real ZIM to it.
mkdir -p "${APP_DIR}/data/kiwix"
if [ ! -f "${APP_DIR}/data/kiwix/library.xml" ]; then
  echo '<?xml version="1.0" encoding="UTF-8"?><library version="20110515"></library>' \
    > "${APP_DIR}/data/kiwix/library.xml"
fi

echo "Starting ollama, ollama-pull, webui, kiwix..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

# webui is routed by Host (not PathPrefix - see docker-compose.yml), so
# hit it through the proxy with an explicit Host header rather than
# relying on /etc/hosts already being configured for this readiness check.
proxy_port=8080
[ -f "${APP_DIR}/../../.env" ] && proxy_port=$(grep -E '^PROXY_HTTP_PORT=' "${APP_DIR}/../../.env" 2>/dev/null | cut -d'=' -f2-)
proxy_port="${proxy_port:-8080}"

echo "Waiting for Open WebUI to come up..."
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null -H "Host: llm.catasophie.local" "http://localhost:${proxy_port}/" 2>/dev/null; then
    break
  fi
  sleep 2
done

if grep -qE '^OPEN_WEBUI_API_KEY=.+' "$ENV_FILE" 2>/dev/null; then
  echo "OPEN_WEBUI_API_KEY already set (skipping manual setup step)"
else
  cat <<EOF

Open WebUI needs a one-time manual step (no API for this part):
  0. Add "llm.catasophie.local" to /etc/hosts, pointing at this box's IP
     (same as you did for catasophie.local, if you haven't already)
  1. Open http://llm.catasophie.local:${proxy_port}/
  2. Create the first account - it becomes the admin
  3. Go to Settings -> Account -> API Keys, and create a key
EOF
  prompt_if_unset OPEN_WEBUI_API_KEY "Paste the Open WebUI API key (blank to skip / do this later)" "" "$ENV_FILE"
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

if [ -n "${OPEN_WEBUI_API_KEY:-}" ]; then
  if confirm "Fetch + ingest the curated corpus now? (downloads several hundred MB-GB)"; then
    "${APP_DIR}/corpus/fetch.sh"
    OPEN_WEBUI_URL="http://localhost:${proxy_port}" \
    OPEN_WEBUI_HOST_HEADER="llm.catasophie.local" \
    OPEN_WEBUI_API_KEY="${OPEN_WEBUI_API_KEY}" \
    "${APP_DIR}/ingest.sh"
  else
    echo "Skipping corpus ingestion - run ./corpus/fetch.sh and ./ingest.sh later."
  fi
else
  echo "No API key set yet - run this installer again, or ./corpus/fetch.sh + ./ingest.sh manually, once you have one."
fi

mark_installed llm-survival
echo "== llm-survival installed. Visit http://llm.catasophie.local:${proxy_port}/ (add it to /etc/hosts first) =="

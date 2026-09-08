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

prompt_if_unset DATA_DIR \
  "Directory for persistent data - ollama models, webui data, kiwix (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

prompt_if_unset LLM_WEBUI_PORT \
  "Port to publish Open WebUI on (http://localhost:<port>/)" \
  "3001" "$ENV_FILE"

prompt_if_unset LLM_KIWIX_PORT \
  "Port to publish Kiwix (WikiMed reference) on (http://localhost:<port>/)" \
  "3002" "$ENV_FILE"

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1

# kiwix-serve needs a valid library.xml to start at all; seed an empty one
# so it comes up cleanly (serving zero books) instead of crash-looping
# until corpus/fetch.sh adds a real ZIM to it.
mkdir -p "${data_dir}/ollama" "${data_dir}/webui" "${data_dir}/kiwix"
if [ ! -f "${data_dir}/kiwix/library.xml" ]; then
  echo '<?xml version="1.0" encoding="UTF-8"?><library version="20110515"></library>' \
    > "${data_dir}/kiwix/library.xml"
fi

echo "Starting ollama, ollama-pull, webui, kiwix..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

webui_port="${LLM_WEBUI_PORT:-3001}"

echo "Waiting for Open WebUI to come up..."
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://localhost:${webui_port}/" 2>/dev/null; then
    break
  fi
  sleep 2
done

if grep -qE '^OPEN_WEBUI_API_KEY=.+' "$ENV_FILE" 2>/dev/null; then
  echo "OPEN_WEBUI_API_KEY already set (skipping manual setup step)"
else
  cat <<EOF

Open WebUI needs a one-time manual step (no API for this part):
  1. Open http://localhost:${webui_port}/ (or http://<device-ip>:${webui_port}/ from another device on the LAN)
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
    OPEN_WEBUI_URL="http://localhost:${webui_port}" \
    OPEN_WEBUI_API_KEY="${OPEN_WEBUI_API_KEY}" \
    "${APP_DIR}/ingest.sh"
  else
    echo "Skipping corpus ingestion - run ./corpus/fetch.sh and ./ingest.sh later."
  fi
else
  echo "No API key set yet - run this installer again, or ./corpus/fetch.sh + ./ingest.sh manually, once you have one."
fi

mark_installed llm-survival
echo "== llm-survival installed. Visit http://localhost:${webui_port}/ =="

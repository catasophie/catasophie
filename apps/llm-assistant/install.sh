#!/usr/bin/env bash
# Interactive installer for llm-assistant (offline LLM chat assistant:
# ollama + open-webui). Idempotent - safe to re-run.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

echo "== llm-assistant install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

default_data_dir=$(resolve_default_data_dir llm-assistant)
prompt_if_unset DATA_DIR \
  "Directory for persistent data - pulled models can be several GB each (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "$default_data_dir" "$ENV_FILE"

prompt_if_unset LLM_ASSISTANT_PORT \
  "Port to publish the chat UI on (http://localhost:<port>/)" \
  "3050" "$ENV_FILE"

prompt_if_unset LLM_ASSISTANT_MODEL \
  "Which Ollama model to pull? (CPU inference only - smaller = faster on modest hardware; see https://ollama.com/library, e.g. llama3.2:3b/qwen2.5:7b/mistral:7b)" \
  "llama3.2:3b" "$ENV_FILE"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1

echo "Starting llm-assistant..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

# Pulling a model is a heavy, fallible, network-dependent step - track
# per-model-tag completion so switching LLM_ASSISTANT_MODEL later (or a
# retry after a failed/interrupted pull) does the right thing: skip if
# this exact model was already pulled, otherwise pull it (ollama itself
# resumes partial pulls, so re-running after an interruption is safe).
model_step="model-pulled:${LLM_ASSISTANT_MODEL}"
if step_done llm-assistant "$model_step"; then
  echo "Model '${LLM_ASSISTANT_MODEL}' already pulled - skipping."
else
  echo "Waiting for ollama to become ready..."
  for _ in $(seq 1 30); do
    podman-compose -f "${APP_DIR}/docker-compose.yml" exec -T ollama ollama list >/dev/null 2>&1 && break
    sleep 2
  done

  echo "Pulling model '${LLM_ASSISTANT_MODEL}' (this can take a while - several GB depending on model size)..."
  if podman-compose -f "${APP_DIR}/docker-compose.yml" exec -T ollama ollama pull "$LLM_ASSISTANT_MODEL"; then
    mark_step_done llm-assistant "$model_step"
  else
    echo "warn: failed to pull '${LLM_ASSISTANT_MODEL}' - re-run this script (or ./up.sh then" >&2
    echo "  podman-compose -f ${APP_DIR}/docker-compose.yml exec ollama ollama pull ${LLM_ASSISTANT_MODEL}) to retry." >&2
  fi
fi

mark_installed llm-assistant
echo "== llm-assistant installed. Visit http://localhost:${LLM_ASSISTANT_PORT:-3050}/ =="

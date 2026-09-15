# llm-assistant

Offline AI chat assistant - [Ollama](https://ollama.com/) runs the
model locally, [Open WebUI](https://openwebui.com/) gives you a
browser-based ChatGPT-style interface on top of it. Entirely local:
after the container images and model are pulled once, no internet
connection is required to use it. Useful as a fallback for questions
the bundled reference content (`apps/wikimed`, etc.) doesn't directly
answer, or as a general-purpose offline assistant.

**CPU-only.** This app doesn't configure any GPU passthrough (no
precedent for that in this repo, and most target hardware here is a
Raspberry Pi or CPU-only mini-PC) - inference runs on the CPU. Small
models (a few billion parameters) are usable, if not fast; large models
will be painfully slow. Pick your model size accordingly.

## One-time setup: pick + pull a model

`install.sh` prompts for `LLM_ASSISTANT_MODEL` (an
[Ollama model tag](https://ollama.com/library)) if it isn't already
configured, and pulls it into the `ollama` container after starting
things up. This is a heavy, one-time (per model) step - even small
models are a couple of GB.

Rough guidance for CPU-only, modest hardware:

| tag | size (approx) | notes |
| --- | --- | --- |
| `llama3.2:3b` (default) | ~2G | fastest, usable on a Raspberry Pi |
| `phi3:mini` | ~2.3G | small, good quality for its size |
| `mistral:7b` | ~4G | noticeably slower on CPU-only, better quality |
| `qwen2.5:7b` | ~4.7G | similar tradeoff to mistral:7b |

Changing your mind later: set `LLM_ASSISTANT_MODEL` to a new tag in
`.env` and re-run `install.sh` (or `up.sh` then pull manually, see
below) - it only pulls what isn't already present, previously-pulled
models stay downloaded (and pulled again next time you switch back).

You can also pull additional models directly without going through
`install.sh`, e.g. to keep more than one available in Open WebUI's
model picker:

```sh
podman-compose -f apps/llm-assistant/docker-compose.yml exec ollama ollama pull mistral:7b
```

## Run

```sh
podman-compose -f apps/llm-assistant/docker-compose.yml up -d
```

Then visit `http://localhost:12020/` (or whatever you set
`LLM_ASSISTANT_PORT` to - also reachable at `http://<device-ip>:12020/`
from another device on the LAN). No login is required by default
(`LLM_ASSISTANT_AUTH=false`) - set it to `true` in `.env` if this
device is reachable beyond a fully trusted LAN.

## Data

Persistent data lives in `./data/ollama/` (pulled models) and
`./data/open-webui/` (chat history/settings), or wherever `DATA_DIR` in
`.env` points (e.g. an external drive) - see `install.sh`.

## Notes

- First response after starting (or after switching models) can be slow
  while the model loads into memory - subsequent responses are faster.
- Telemetry: Open WebUI's embedded vector store (chromadb) telemetry is
  disabled (`ANONYMIZED_TELEMETRY=false`); no other network calls are
  made once images/models are pulled.

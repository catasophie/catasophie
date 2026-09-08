# llm-survival

Offline LLM assistant focused on survival and medical reference, backed by
a curated corpus so answers can cite real sources instead of relying
purely on model weights.

## Components

- **ollama** - runs the model (`${OLLAMA_MODEL}`, default `llama3.2:3b`) -
  internal only, not reachable directly
- **webui** ([Open WebUI](https://github.com/open-webui/open-webui)) - chat
  frontend with built-in document/knowledge-base RAG + citations.
  Published on `http://localhost:${LLM_WEBUI_PORT:-3001}/`
- **kiwix** - serves the WikiMed offline medical encyclopedia as a
  browsable supplementary reference, published on
  `http://localhost:${LLM_KIWIX_PORT:-3002}/`

## First run

```sh
./apps/llm-survival/install.sh
```

(or `podman-compose -f apps/llm-survival/docker-compose.yml up -d` by
hand). This pulls the model (`ollama-pull` runs once and exits) and
starts Open WebUI, reachable at `http://localhost:3001/` (or whatever
you set `LLM_WEBUI_PORT` to - also reachable at
`http://<device-ip>:3001/` from another device on the LAN). Create
the first account there (it becomes the admin) and generate an API key
under **Settings -> Account -> API Keys** - `install.sh` will prompt you
for it.

## Loading the curated corpus

```sh
cd apps/llm-survival
./corpus/fetch.sh                                  # downloads PDFs + WikiMed ZIM into corpus/data/raw/
OPEN_WEBUI_URL=http://localhost:3001 \
OPEN_WEBUI_API_KEY=sk-... \
./ingest.sh                                        # uploads PDFs into an Open WebUI knowledge collection
```

See `corpus/sources.yaml` for the list of sources and their licenses -
review the Hesperian entry's terms before distributing this box beyond
personal/household use. Neither `fetch.sh` nor `ingest.sh` run
automatically; both are safe to re-run (idempotent). `corpus/fetch.sh`
also seeds `kiwix`'s library once the WikiMed ZIM is downloaded - restart
the `kiwix` service afterward to pick it up.

Once loaded, select the **Survival & Medical** knowledge collection as a
context source in Open WebUI (`#` reference in chat, or
Workspace -> Knowledge) so responses cite the underlying documents.

## Sizing the model

- Raspberry Pi / constrained hardware: `phi3:mini`, `llama3.2:3b`
- Laptop / mini-PC (16GB+ RAM): `llama3.1:8b`, `gemma2:9b`

Change `OLLAMA_MODEL` in `.env` and re-run `podman-compose -f
apps/llm-survival/docker-compose.yml up -d ollama-pull`.

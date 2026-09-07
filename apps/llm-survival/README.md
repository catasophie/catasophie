# llm-survival

Offline LLM assistant focused on survival and medical reference, backed by
a curated corpus so answers can cite real sources instead of relying
purely on model weights.

## Components

- **ollama** - runs the model (`${OLLAMA_MODEL}`, default `llama3.2:3b`)
- **webui** ([Open WebUI](https://github.com/open-webui/open-webui)) - chat
  frontend with built-in document/knowledge-base RAG + citations. Routed
  by **hostname** (`llm.catasophie.local`), not a path prefix - Open
  WebUI's frontend has no configurable base path, so path-based routing
  breaks its asset loading.
- **kiwix** - serves the WikiMed offline medical encyclopedia as a
  browsable supplementary reference at `/llm/kiwix/` (path-based routing
  works fine here since kiwix-serve is proxied with a strip-prefix)

## One-time setup: hostname

Add this to `/etc/hosts` on any machine you'll browse from, pointing at
the box's IP (same as you already do for `catasophie.local`):

```
<box-ip>  llm.catasophie.local
```

## First run

```sh
./apps/llm-survival/install.sh
```

(or `podman-compose -f apps/llm-survival/docker-compose.yml up -d` by
hand). This pulls the model (`ollama-pull` runs once and exits) and
starts Open WebUI, reachable at `http://llm.catasophie.local:8080/`
(replace `8080` with your `PROXY_HTTP_PORT` if you changed it). Create
the first account there (it becomes the admin) and generate an API key
under **Settings -> Account -> API Keys** - `install.sh` will prompt you
for it.

## Loading the curated corpus

```sh
cd apps/llm-survival
./corpus/fetch.sh                                  # downloads PDFs + WikiMed ZIM into corpus/data/raw/
OPEN_WEBUI_URL=http://llm.catasophie.local:8080 \
OPEN_WEBUI_API_KEY=sk-... \
./ingest.sh                                        # uploads PDFs into an Open WebUI knowledge collection
```

If `llm.catasophie.local` isn't resolvable from where you're running
`ingest.sh` (e.g. running it directly on the box before setting up
`/etc/hosts` there too), use the Host-header form instead:

```sh
OPEN_WEBUI_URL=http://localhost:8080 \
OPEN_WEBUI_HOST_HEADER=llm.catasophie.local \
OPEN_WEBUI_API_KEY=sk-... \
./ingest.sh
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

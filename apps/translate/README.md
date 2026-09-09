# translate

Offline machine translation, powered by
[LibreTranslate](https://github.com/LibreTranslate/LibreTranslate)
(engine: [Argos Translate](https://github.com/argosopentech/argos-translate)).
A single container serves both a web UI and a JSON API
(`/translate`, `/detect`, `/languages`) on one port - no separate
frontend/backend split needed.

## One-time setup

Language models must be downloaded once (needs internet access) before
translation works - run:

```sh
./apps/translate/scripts/select-languages.sh
```

This is also run automatically by `install.sh`. It shows a checklist of
common languages (pre-checked with whatever's currently loaded), then
downloads models for every pair among the selected languages -
roughly 150-200MB per language, more for some. Re-run this script any
time later to add or remove languages - it only re-downloads what
changed, and safely re-recreates the container without leftover
one-time flags afterward. Non-interactive form:

```sh
TRANSLATE_LANGS=en,es,fr,de ./apps/translate/scripts/select-languages.sh
```

See <https://libretranslate.com/languages> for the full list of valid
ISO codes (not limited to what's offered in the checklist).

Once models are downloaded, translate works **entirely offline** -
no internet needed at runtime, only when adding new languages.

## Run

```sh
./apps/translate/up.sh
```

Then visit `http://localhost:3030/` (or whatever you set
`TRANSLATE_PORT` to in `.env` - also reachable at
`http://<device-ip>:3030/` from another device on the LAN).

Stop with `./apps/translate/down.sh`.

## Data

Downloaded language models live in `./data/` (gitignored), or wherever
`DATA_DIR` in `.env` points (e.g. an external drive) - see `install.sh`.
They're owned by the container's fixed non-root uid (1032); the install
scripts handle this automatically (`podman unshare chown`), you
shouldn't need to touch it yourself.

## Notes

- The official image is multi-arch (amd64 + arm64), so this runs fine
  on a Raspberry Pi.
- Loading many languages at once increases both download size and the
  container's memory/CPU usage at runtime - keep the selection to what
  you actually need on modest hardware.

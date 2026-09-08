# wikimed

Offline medical/survival reference content, served entirely from
locally stored [Kiwix](https://kiwix.org/) ZIM files - no internet
required once set up. Uses
[kiwix-serve](https://github.com/kiwix/kiwix-tools/blob/main/docker/server/README.md)
to serve whatever ZIM(s) you download.

## One-time setup: download content

`scripts/download-zim.sh` prompts for which content to fetch
(`WIKIMED_ZIMS`) if it isn't already configured, and persists your
answer to this app's `.env`. `make install ARGS="wikimed"` calls it for
you automatically after asking the questions it needs itself (data
directory, port). The prompt is a toggleable checklist (space to
toggle, enter to confirm, via `whiptail`/`dialog` if installed,
otherwise a plain numbered multi-select) - so you can grab more than one
at once. Pick from:

| key | size (approx) | description |
| --- | --- | --- |
| `zimgit-medicine` (default) | ~70M | Offline survival medicine guide (Zimgit project, purpose-built for no-internet/disaster use) |
| `zimgit-post-disaster` | ~600M | Broader post-disaster survival guide |
| `zimgit-water` | ~20M | Water safety/purification |
| `zimgit-food-preparation` | ~90M | Food safety/preparation |
| `zimgit-knots` | ~30M | Practical knots reference |
| `wikem` | ~360M | [WikEM](https://www.wikem.org/) - global emergency medicine wiki |
| `mdwiki` | ~2G | The full ["WikiMed" Medical Encyclopedia](https://mdwiki.org/) - comprehensive general medical reference |

You can also add one-off content not in the catalog via a `custom:<url>`
entry (not offered in the checklist - set `WIKIMED_ZIMS` directly, see
below) pointing at any `.zim` file - browse
[library.kiwix.org](https://library.kiwix.org/) or
[download.kiwix.org/zim/](https://download.kiwix.org/zim/) for more
(other useful categories there: Wikipedia subsets, Wiktionary,
WikiHow, Project Gutenberg, etc.).

Or run the download script directly (e.g. to fetch ahead of time,
before running the installer, or to add more content later) - either
interactively, or non-interactively by passing the answer as an
environment variable (this takes precedence over the prompt, and gets
saved to `.env` too):

```sh
WIKIMED_ZIMS="zimgit-medicine wikem" ./apps/wikimed/scripts/download-zim.sh
WIKIMED_ZIMS="zimgit-medicine custom:https://example.com/some.zim" ./apps/wikimed/scripts/download-zim.sh
```

This downloads each requested ZIM into `apps/wikimed/data/zims/`
(gitignored, or wherever `DATA_DIR` in `.env` points - see the root
README's "Storing data on an external drive" section). Already-present
ZIMs are skipped, so re-running only fetches what's missing - e.g. to
add `wikem` later without re-downloading `zimgit-medicine`, just re-run
with `WIKIMED_ZIMS="zimgit-medicine wikem"`.

Adding a brand-new catalog entry for the future: edit the `CATALOG`
associative array at the top of `scripts/download-zim.sh` - no other
changes needed, `kiwix-serve` (see `docker-compose.yml`) already globs
every `.zim` file under `data/zims/`.

This is a heavy step for the larger entries - expect multi-GB downloads
to take a while. The default (`zimgit-medicine`) is small and fast.

## Run

```sh
podman-compose -f apps/wikimed/docker-compose.yml up -d
```

Then visit `http://localhost:3020/` (or whatever you set
`WIKIMED_PORT` to - also reachable at `http://<device-ip>:3020/`
from another device on the LAN).

## Data

Persistent data (downloaded ZIM files) lives in `./data/zims/`
(gitignored), or wherever `DATA_DIR` in `.env` points (e.g. an external
drive) - see `install.sh`.

## Notes

- Filenames upstream on `download.kiwix.org` are dated and get replaced
  periodically. If a catalog download 404s, check
  `https://download.kiwix.org/zim/other/` for the current filename and
  either bump the URL in `scripts/download-zim.sh` or work around it
  with a one-off `custom:<url>` entry in `WIKIMED_ZIMS`.
- Each ZIM is downloaded once to a stable filename
  (`data/zims/<key>.zim`) - it won't auto-update to a newer dated
  upstream file. To refresh a given entry, delete its file under
  `data/zims/` and re-run `scripts/download-zim.sh`.

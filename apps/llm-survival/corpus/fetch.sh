#!/usr/bin/env bash
# Downloads the curated corpus into ./data/raw/ (gitignored). Idempotent -
# skips files that already exist. Mirrors the entries in sources.yaml
# (kept here as a plain bash table too, so this script has zero extra
# dependencies beyond curl/sha256sum).
#
# NOTE: verify each URL still resolves before relying on it - hosting
# paths on archive.org/government/NGO sites change over time. Update both
# this script and sources.yaml if a URL moves.
#
# After running, copy the printed sha256 values into corpus/sources.yaml
# for future integrity verification.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p data/raw

# id | url | filename
entries=(
  "fm21-76-survival-manual|https://archive.org/download/FM21-76-1/FM21-76-1.pdf|fm21-76-survival-manual.pdf"
  "fema-are-you-ready|https://www.fema.gov/pdf/areyouready/areyouready_full.pdf|fema-are-you-ready.pdf"
  "wikimed|https://download.kiwix.org/zim/wikipedia/wikipedia_en_medicine_maxi.zim|wikimed.zim"
  "hesperian-where-there-is-no-doctor|https://hesperian.org/wp-content/uploads/pdf/en_wtnd_2018/en_wtnd_2018_full.pdf|hesperian-where-there-is-no-doctor.pdf"
)

for entry in "${entries[@]}"; do
  IFS='|' read -r id url filename <<< "$entry"
  dest="data/raw/$filename"
  if [ -f "$dest" ]; then
    echo "skip (already downloaded): $filename"
    continue
  fi
  echo "downloading $id from $url ..."
  if curl -fL --retry 3 -o "$dest.part" "$url"; then
    mv "$dest.part" "$dest"
    printf '%s  sha256: %s\n' "$filename" "$(sha256sum "$dest" | cut -d' ' -f1)"
  else
    echo "warn: failed to download $id ($url) - check the URL is still valid" >&2
    rm -f "$dest.part"
  fi
done

# The kiwix ZIM needs a library.xml for kiwix-serve to find it. Uses the
# same containerized kiwix-manage as the running kiwix-serve image, so it
# doesn't depend on kiwix tools being installed on the host.
if [ -f data/raw/wikimed.zim ]; then
  mkdir -p ../data/kiwix
  cp -n data/raw/wikimed.zim ../data/kiwix/wikimed.zim
  if [ ! -f ../data/kiwix/library.xml ]; then
    echo '<?xml version="1.0" encoding="UTF-8"?><library version="20110515"></library>' \
      > ../data/kiwix/library.xml
  fi
  podman run --rm -v "$(pwd)/../data/kiwix:/data" --entrypoint kiwix-manage \
    ghcr.io/kiwix/kiwix-serve:latest /data/library.xml add /data/wikimed.zim
  echo "Restart the kiwix service to pick up the new library: podman-compose -f ../docker-compose.yml restart kiwix"
fi

echo "Done. PDFs are in data/raw/ - run ./ingest.sh to load them into Open WebUI's knowledge base."

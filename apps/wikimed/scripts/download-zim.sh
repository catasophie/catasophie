#!/usr/bin/env bash
# Downloads one or more Kiwix ZIM files (offline wikis/reference content)
# into ${DATA_DIR:-./data}/zims/ for kiwix-serve to pick up (see
# ../docker-compose.yml, which globs *.zim in that folder).
#
# This is a heavy, one-time (or per-content-change) setup step - some
# ZIMs are multi-GB. Not run automatically by anything else in this repo
# except apps/wikimed/install.sh (which just calls this script
# unconditionally - all content-related prompting/config lives here, the
# same pattern as apps/offline-maps/scripts/import-region.sh).
#
# Self-contained/idempotent: prompts (and persists to this app's .env)
# for WIKIMED_ZIMS if it isn't already set, so it's safe to run directly,
# without install.sh, on a fresh checkout. Values already exported in the
# process environment take precedence over .env and skip the prompt too
# (see prompt_if_unset in apps/cli/scripts/lib/common.sh), so the
# non-interactive form below still works:
#
#   WIKIMED_ZIMS="zimgit-medicine wikem" ./scripts/download-zim.sh
#
# WIKIMED_ZIMS is a space-separated list of entries, each either:
#   - a catalog key (see CATALOG below), e.g. zimgit-medicine
#   - a custom one-off URL: custom:https://example.com/some.zim (saved
#     to data/zims/custom-<n>.zim)
#
# Resumable: each ZIM only downloads if its final output isn't already
# present (data/zims/<key>.zim), and downloads write to a temporary
# ".part" file first, only moving into the real final path once they
# fully succeed - so a crash/interruption partway through never leaves
# behind a partial file that looks complete. Re-run this script to pick
# up wherever it left off. Note: filenames are stable per key (not
# upstream's dated filename), so bumping a catalog entry's URL to a
# newer dated file later requires deleting the old data/zims/<key>.zim
# first to force a re-download (same convention as offline-maps' regions
# - imported data isn't auto-updated).
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

# Known-good ZIMs from https://download.kiwix.org/zim/other/ as of
# writing - dated filenames upstream can go stale (get replaced by a
# newer date) over time. If a download 404s, check
# https://download.kiwix.org/zim/other/ for the current filename and
# either bump the URL below or use a custom:<url> entry in WIKIMED_ZIMS
# to override without editing this script.
declare -A CATALOG=(
  [zimgit-medicine]="https://download.kiwix.org/zim/other/zimgit-medicine_en_2024-08.zim"
  [zimgit-post-disaster]="https://download.kiwix.org/zim/other/zimgit-post-disaster_en_2024-05.zim"
  [zimgit-water]="https://download.kiwix.org/zim/other/zimgit-water_en_2024-08.zim"
  [zimgit-food-preparation]="https://download.kiwix.org/zim/other/zimgit-food-preparation_en_2024-08.zim"
  [zimgit-knots]="https://download.kiwix.org/zim/other/zimgit-knots_en_2024-08.zim"
  [wikem]="https://download.kiwix.org/zim/other/wikem_en_all_maxi_2026-07.zim"
  [mdwiki]="https://download.kiwix.org/zim/other/mdwiki_en_all_maxi_2025-11.zim"
)

catalog_keys() {
  local k keys=()
  for k in "${!CATALOG[@]}"; do keys+=("$k"); done
  IFS=$'\n' sort <<<"${keys[*]}"
}

# Toggleable checklist (whiptail/dialog if available, else a numbered
# multi-select prompt) - see apps/wikimed/README.md for what each key
# contains. Custom one-off URLs aren't offered here (they're not a fixed
# list of options); add them by setting WIKIMED_ZIMS yourself, e.g.:
#   WIKIMED_ZIMS="zimgit-medicine custom:https://example.com/some.zim" ./scripts/download-zim.sh
prompt_multi_choice_if_unset WIKIMED_ZIMS \
  "Which ZIM(s) to download? (space to toggle, enter to confirm - see apps/wikimed/README.md for descriptions)" \
  "$(catalog_keys | tr '\n' ' ')" "zimgit-medicine" "$ENV_FILE"

: "${WIKIMED_ZIMS:?WIKIMED_ZIMS is required (see prompt above, or set it in ${ENV_FILE})}"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1
zims_dir="${data_dir}/zims"
mkdir -p "$zims_dir"

# Resolve requested entries to (name, url) pairs up front, so we can show
# a summary and confirm once before downloading anything.
names=() urls=()
custom_n=0
for entry in $WIKIMED_ZIMS; do
  case "$entry" in
    custom:*)
      custom_n=$((custom_n + 1))
      names+=("custom-${custom_n}")
      urls+=("${entry#custom:}")
      ;;
    *)
      if [ -z "${CATALOG[$entry]:-}" ]; then
        echo "error: unknown ZIM key '${entry}' - available: $(catalog_keys | tr '\n' ' ')" >&2
        echo "  (or use a custom:<url> entry)" >&2
        exit 1
      fi
      names+=("$entry")
      urls+=("${CATALOG[$entry]}")
      ;;
  esac
done

to_fetch_names=() to_fetch_urls=()
echo "Requested content:"
for i in "${!names[@]}"; do
  final="${zims_dir}/${names[$i]}.zim"
  if [ -f "$final" ]; then
    echo "  - ${names[$i]}: already downloaded (${final}) - skipping"
  else
    echo "  - ${names[$i]}: ${urls[$i]}"
    to_fetch_names+=("${names[$i]}")
    to_fetch_urls+=("${urls[$i]}")
  fi
done

if [ "${#to_fetch_names[@]}" -eq 0 ]; then
  echo "Nothing new to download."
  exit 0
fi

if ! confirm "Download ${#to_fetch_names[@]} ZIM(s) now? (heavy: can be multi-GB and take a long time)"; then
  echo "Skipping download - re-run ${APP_DIR}/scripts/download-zim.sh (or make install ARGS=\"wikimed\") when ready."
  exit 0
fi

for i in "${!to_fetch_names[@]}"; do
  name="${to_fetch_names[$i]}"
  url="${to_fetch_urls[$i]}"
  final="${zims_dir}/${name}.zim"
  echo "Downloading ${name} from ${url}..."
  curl -fL --retry 3 -o "${final}.part" "$url"
  mv "${final}.part" "$final"
done

echo
echo "Done. WIKIMED_ZIMS=${WIKIMED_ZIMS} is set in ${ENV_FILE}. Start the app with:"
echo "  podman-compose -f ${APP_DIR}/docker-compose.yml up -d"

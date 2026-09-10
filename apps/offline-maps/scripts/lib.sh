# Shared functions for importing OSM regions and (re)generating the
# tileserver-gl config that serves all of them side by side. Sourced by
# both scripts/import-region.sh (first region, wired into install.sh)
# and scripts/add-region.sh (any additional region afterwards) - keep
# both call sites in sync if you change behavior here.
#
# Not meant to be run directly.

# Turns a region path/name (e.g. "europe/germany", "North Rhine",
# "us-west") into a safe, unique identifier usable as a filename stem,
# a tileserver-gl data/style id, and inside a "mbtiles://{id}" style
# source URL (see templates/style.json.template) - lowercase
# alphanumerics, dashes and underscores only. Only the last path
# component is used (e.g. "europe/germany" -> "germany") to match
# older versions of this app (pre-multi-region support) that named
# their single .mbtiles/.env MAP_REGION that way - so upgrading an
# existing single-region install doesn't orphan its already-built
# tiles.
region_id() {
  local raw
  raw="$(basename "$1")"
  echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9_-]+#-#g; s#^-+##; s#-+$##'
}

# Echoes the .osm.pbf download URL for the given source/region, unless
# source_url_override is non-empty (in which case that's used as-is).
resolve_source_url() {
  local source="$1" region="$2" source_url_override="$3"

  if [ -n "$source_url_override" ]; then
    echo "$source_url_override"
    return 0
  fi

  case "$source" in
  osmfr)
    echo "https://download.openstreetmap.fr/extracts/${region}-latest.osm.pbf"
    ;;
  bbbike)
    echo "https://download.bbbike.org/osm/bbbike/${region}/${region}.osm.pbf"
    ;;
  *)
    echo "https://download.geofabrik.de/${region}-latest.osm.pbf"
    ;;
  esac
}

# Downloads the extract (if not already present) and builds an
# .mbtiles vector tileset for it (if not already built) into
# "${data_dir}/tiles/${id}.mbtiles". Resumable: the download and the
# build each only run if their final output isn't already present, and
# the build writes into a temporary ".building" dir first, only moving
# into the real final path once it fully succeeds.
# Usage: import_region_tiles <data_dir> <id> <display_name> <source_url>
import_region_tiles() {
  local data_dir="$1" id="$2" display_name="$3" source_url="$4"

  mkdir -p "${data_dir}/raw" "${data_dir}/tiles"
  local pbf="${data_dir}/raw/${id}-latest.osm.pbf"
  local mbtiles_final="${data_dir}/tiles/${id}.mbtiles"

  # Sidecar file recording the human-readable name (MAP_REGION/region as
  # typed, before sanitizing into $id) - regenerate_tiles_config reads
  # it back to label the style nicely in the region picker. Written
  # unconditionally (even on the "already built" fast path) so it stays
  # in sync if this ever gets re-run with a different display name for
  # the same id.
  echo "$display_name" >"${data_dir}/tiles/${id}.name"

  if [ -f "$mbtiles_final" ]; then
    echo "Vector tiles already built for '${display_name}' (${mbtiles_final}) - skipping"
    return 0
  fi

  if ! confirm "Run the import for '${display_name}' now? (heavy: multi-GB download + processing, can take a long time)"; then
    echo "Skipping import - re-run this script when ready to pick up where it left off."
    return 1
  fi

  if [ ! -f "$pbf" ]; then
    echo "Downloading ${display_name} extract from ${source_url}..."
    curl -fL --retry 3 -o "$pbf.part" "$source_url"
    mv "$pbf.part" "$pbf"
  else
    echo "Using existing extract: $pbf"
  fi

  echo "== Building vector tiles for '${display_name}' (Planetiler) =="
  local build_dir="${data_dir}/tiles/.building"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  podman run --rm \
    -v "${data_dir}/raw:/data/raw" \
    -v "${build_dir}:/data/tiles" \
    -e JAVA_TOOL_OPTIONS="-Xmx5g" \
    ghcr.io/onthegomap/planetiler:latest \
    --download --area="${id}" --osm-path="/data/raw/${id}-latest.osm.pbf" \
    --output="/data/tiles/${id}.mbtiles"
  mv "${build_dir}/${id}.mbtiles" "$mbtiles_final"
  rm -rf "$build_dir"
}

# Writes one styles/<id>/style.json (from templates/style.json.template)
# per already-built "${data_dir}/tiles/<id>.mbtiles", and rewrites
# tiles/config.json to register all of them as separate data sources +
# styles, so tileserver-gl serves every imported region side by side
# (picked at runtime by the web frontend via /styles.json - see
# web/index.html). Safe to call any time - it fully regenerates both
# from whatever .mbtiles files currently exist on disk, so it's the
# single source of truth (no separate "which regions are imported"
# state to keep in sync elsewhere).
# Usage: regenerate_tiles_config <data_dir> <style_template_path>
regenerate_tiles_config() {
  local data_dir="$1" style_template="$2"
  local tiles_dir="${data_dir}/tiles"
  mkdir -p "${tiles_dir}/styles"

  local id mbtiles data_entries="" style_entries="" first=1 display_name
  for mbtiles in "${tiles_dir}"/*.mbtiles; do
    [ -e "$mbtiles" ] || continue
    id="$(basename "$mbtiles" .mbtiles)"
    display_name="$id"
    [ -f "${tiles_dir}/${id}.name" ] && display_name="$(cat "${tiles_dir}/${id}.name")"

    mkdir -p "${tiles_dir}/styles/${id}"
    sed -e "s#__REGION_ID__#${id}#g" -e "s#__REGION_NAME__#${display_name}#g" \
      "$style_template" >"${tiles_dir}/styles/${id}/style.json"

    if [ "$first" -eq 0 ]; then
      data_entries+=","
      style_entries+=","
    fi
    first=0
    data_entries+=$'\n'"    \"${id}\": { \"mbtiles\": \"${id}.mbtiles\" }"
    style_entries+=$'\n'"    \"${id}\": { \"style\": \"/data/styles/${id}/style.json\" }"
  done

  if [ -z "$data_entries" ]; then
    echo "No .mbtiles files found under ${tiles_dir} - nothing to configure yet." >&2
    return 1
  fi

  # "paths.mbtiles" is "/data" (this app's docker-compose mounts
  # tiles_dir there) - style paths above are given as absolute
  # "/data/styles/<id>/style.json" so they resolve regardless of
  # "paths.styles" (tileserver-gl's path.resolve() leaves absolute
  # paths untouched - see server.js's addStyle()). "paths.root" still
  # points at the image's own bundled fonts dir, which we still need.
  cat >"${tiles_dir}/config.json" <<EOF
{
  "options": {
    "paths": {
      "root": "/usr/src/app/node_modules/tileserver-gl-styles",
      "fonts": "fonts",
      "mbtiles": "/data"
    }
  },
  "styles": {${style_entries}
  },
  "data": {${data_entries}
  }
}
EOF

  echo "Registered $(printf '%s\n' "${tiles_dir}"/*.mbtiles | wc -l) region(s) in ${tiles_dir}/config.json"
}

#!/usr/bin/env bash
# Shared helpers sourced by root and per-app install/update scripts.
# Not meant to be executed directly.

CATASOPHIE_ROOT="${CATASOPHIE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
INSTALLED_MARKER_FILE="${CATASOPHIE_ROOT}/.installed"

# Fails with a clear message if required tools aren't on PATH.
check_deps() {
  local missing=()
  command -v podman >/dev/null 2>&1 || missing+=("podman")
  command -v podman-compose >/dev/null 2>&1 || missing+=("podman-compose")
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "error: missing required tool(s): ${missing[*]}" >&2
    echo "See https://podman.io/docs/installation and https://github.com/containers/podman-compose" >&2
    exit 1
  fi
}

# Copies .env.example -> .env in the given app dir if .env doesn't exist yet.
ensure_env_file() {
  local app_dir="$1"
  if [ ! -f "$app_dir/.env" ] && [ -f "$app_dir/.env.example" ]; then
    cp "$app_dir/.env.example" "$app_dir/.env"
  fi
  touch "$app_dir/.env"
}

# Reads VAR from env_file; if unset/empty, prompts interactively (showing
# a default if given) and appends/updates it in env_file.
# Usage: prompt_if_unset VAR_NAME "Prompt text" ["default value"] "path/to/.env"
prompt_if_unset() {
  local var_name="$1" prompt_text="$2" default_value="$3" env_file="$4"
  local current
  current=$(grep -E "^${var_name}=" "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2-)

  if [ -n "$current" ]; then
    echo "  ${var_name} already set (skipping prompt)"
    return 0
  fi

  local answer
  if [ -n "$default_value" ]; then
    read -r -p "${prompt_text} [${default_value}]: " answer
    answer="${answer:-$default_value}"
  else
    read -r -p "${prompt_text}: " answer
  fi

  if grep -qE "^${var_name}=" "$env_file" 2>/dev/null; then
    sed -i.bak "s#^${var_name}=.*#${var_name}=${answer}#" "$env_file" && rm -f "$env_file.bak"
  else
    echo "${var_name}=${answer}" >> "$env_file"
  fi
}

# Asks a yes/no question. Returns 0 for yes, 1 for no. Default is "no"
# unless second arg is "y".
confirm() {
  local prompt_text="$1" default="${2:-n}" answer
  local hint="y/N"
  [ "$default" = "y" ] && hint="Y/n"
  read -r -p "${prompt_text} [${hint}]: " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

# Detects the podman API socket path (preferring the rootless per-user
# socket) and writes it into the root .env if PODMAN_SOCK isn't already
# set there. Traefik needs this to watch containers via labels.
ensure_podman_sock() {
  local env_file="${CATASOPHIE_ROOT}/.env"
  touch "$env_file"
  local current
  current=$(grep -E "^PODMAN_SOCK=" "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
  if [ -n "$current" ]; then
    return 0
  fi

  local sock=""
  if command -v podman >/dev/null 2>&1; then
    sock=$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)
  fi
  if [ -z "$sock" ] || [ ! -S "$sock" ]; then
    sock="/run/user/$(id -u)/podman/podman.sock"
  fi

  if [ ! -S "$sock" ]; then
    echo "warn: podman socket not found/active at $sock" >&2
    echo "  enable it with: systemctl --user enable --now podman.socket" >&2
  fi

  if grep -qE "^PODMAN_SOCK=" "$env_file" 2>/dev/null; then
    sed -i.bak "s#^PODMAN_SOCK=.*#PODMAN_SOCK=${sock}#" "$env_file" && rm -f "$env_file.bak"
  else
    echo "PODMAN_SOCK=${sock}" >> "$env_file"
  fi
  echo "  detected podman socket: ${sock}"
}

mark_installed() {
  local app_id="$1"
  touch "$INSTALLED_MARKER_FILE"
  grep -qxF "$app_id" "$INSTALLED_MARKER_FILE" || echo "$app_id" >> "$INSTALLED_MARKER_FILE"
}

is_installed() {
  local app_id="$1"
  [ -f "$INSTALLED_MARKER_FILE" ] && grep -qxF "$app_id" "$INSTALLED_MARKER_FILE"
}

list_installed() {
  [ -f "$INSTALLED_MARKER_FILE" ] && cat "$INSTALLED_MARKER_FILE" || true
}

# Every installable app has apps/<id>/install.sh, except the _template.
list_available_apps() {
  local dir
  for dir in "${CATASOPHIE_ROOT}"/apps/*/; do
    local id
    id=$(basename "$dir")
    [ "$id" = "_template" ] && continue
    [ -f "${dir}install.sh" ] && echo "$id"
  done
}

# === Backup / restore / rollback ===
#
# Backups live in backups/<app-id>/<timestamp>/ (root state uses the
# pseudo-app-id "_root"). Each backup dir may contain:
#   .env               - copy of the app's .env at backup time
#   data.tar.gz          - tar of the app's bind-mounted ./data (if any)
#   volume__<name>.tar    - podman volume export, one per named volume
#
# Volume naming: podman-compose derives volume names as
# "<project-name>_<volume-key>", where project-name defaults to the
# compose file's directory name - i.e. exactly the app id. This is
# confirmed against actually-running volumes, not just assumed.

BACKUPS_DIR="${CATASOPHIE_ROOT}/backups"

# Prints "<app_id>_<volume-key>" for every top-level named volume declared
# in apps/<app_id>/docker-compose.yml (root compose file if app_id is
# "_root").
app_volume_names() {
  local app_id="$1" compose_file project
  compose_file=$(_compose_file_for "$app_id")
  project=$(_project_name_for "$app_id")
  [ -f "$compose_file" ] || return 0
  awk '
    /^volumes:/ { f=1; next }
    /^[^ ]/ { f=0 }
    f && /^  [A-Za-z0-9_-]+:/ { gsub(/^  /,""); gsub(/:.*/,""); print }
  ' "$compose_file" | while read -r vol; do
    echo "${project}_${vol}"
  done
}

# Returns the app's compose file path, or the root one for "_root".
_compose_file_for() {
  local app_id="$1"
  if [ "$app_id" = "_root" ]; then
    echo "${CATASOPHIE_ROOT}/docker-compose.yml"
  else
    echo "${CATASOPHIE_ROOT}/apps/${app_id}/docker-compose.yml"
  fi
}

# Returns the app's directory, or repo root for "_root".
_app_dir_for() {
  local app_id="$1"
  if [ "$app_id" = "_root" ]; then
    echo "${CATASOPHIE_ROOT}"
  else
    echo "${CATASOPHIE_ROOT}/apps/${app_id}"
  fi
}

# podman-compose's project name (used in container labels) defaults to
# the compose file's directory name - "catasophie" for the root stack,
# not the pseudo-id "_root" used elsewhere in this file.
_project_name_for() {
  local app_id="$1"
  if [ "$app_id" = "_root" ]; then
    basename "$CATASOPHIE_ROOT"
  else
    echo "$app_id"
  fi
}

# Backs up one app's (or "_root"'s) .env, bind-mounted data/, and named
# volumes into dest_dir. For offline-maps specifically, data/raw/ (the
# source OSM extract, re-downloadable via import-region.sh) is excluded
# to keep backups smaller/faster.
backup_app() {
  local app_id="$1" dest_dir="$2"
  local app_dir; app_dir=$(_app_dir_for "$app_id")
  local project; project=$(_project_name_for "$app_id")
  mkdir -p "$dest_dir"

  if [ -f "${app_dir}/.env" ]; then
    cp "${app_dir}/.env" "${dest_dir}/.env"
  fi

  if [ -d "${app_dir}/data" ]; then
    echo "  backing up ${app_id}/data/ ..."
    local tar_excludes=()
    if [ "$app_id" = "offline-maps" ]; then
      tar_excludes+=(--exclude="data/raw")
    fi
    tar czf "${dest_dir}/data.tar.gz" "${tar_excludes[@]}" -C "$app_dir" data
  fi

  local vol
  while IFS= read -r vol; do
    [ -z "$vol" ] && continue
    if podman volume exists "$vol" 2>/dev/null; then
      echo "  exporting volume ${vol} ..."
      podman volume export "$vol" -o "${dest_dir}/volume__${vol#${project}_}.tar"
    fi
  done < <(app_volume_names "$app_id")

  echo "$dest_dir"
}

# Deletes backups beyond the most recent $keep (default 5) for the given
# app id.
prune_backups() {
  local app_id="$1" keep="${2:-5}"
  local app_backup_dir="${BACKUPS_DIR}/${app_id}"
  [ -d "$app_backup_dir" ] || return 0
  local -a dirs
  mapfile -t dirs < <(find "$app_backup_dir" -mindepth 1 -maxdepth 1 -type d | sort)
  local total="${#dirs[@]}"
  if [ "$total" -gt "$keep" ]; then
    local excess=$((total - keep))
    local i
    for ((i = 0; i < excess; i++)); do
      echo "  pruning old backup: ${dirs[$i]}"
      rm -rf "${dirs[$i]}"
    done
  fi
}

# Resolves "latest" (or a literal timestamp) to an actual backup dir for
# the given app id.
resolve_backup_dir() {
  local app_id="$1" which="${2:-latest}"
  local app_backup_dir="${BACKUPS_DIR}/${app_id}"
  if [ "$which" = "latest" ]; then
    find "$app_backup_dir" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1
  else
    echo "${app_backup_dir}/${which}"
  fi
}

# Restores an app's .env, data/, and named volumes from a backup dir,
# stopping/starting the app's containers around the restore. Set
# ASSUME_YES=1 to skip the confirmation prompt.
restore_app() {
  local app_id="$1" backup_dir="$2"
  local app_dir; app_dir=$(_app_dir_for "$app_id")
  local compose_file; compose_file=$(_compose_file_for "$app_id")
  local project; project=$(_project_name_for "$app_id")

  if [ ! -d "$backup_dir" ]; then
    echo "error: backup dir not found: $backup_dir" >&2
    return 1
  fi

  if [ "${ASSUME_YES:-0}" != "1" ]; then
    echo "About to restore ${app_id} from ${backup_dir}:"
    [ -f "${backup_dir}/.env" ] && echo "  - .env will be overwritten"
    [ -f "${backup_dir}/data.tar.gz" ] && echo "  - ${app_dir}/data/ will be replaced"
    for f in "${backup_dir}"/volume__*.tar; do
      [ -e "$f" ] || continue
      echo "  - volume $(basename "$f" .tar | sed 's/^volume__//') will be replaced"
    done
    local answer
    read -r -p "Type 'yes' to continue: " answer
    [ "$answer" = "yes" ] || { echo "Aborted."; return 1; }
  fi

  if [ -f "$compose_file" ]; then
    echo "  stopping ${app_id}..."
    podman-compose -f "$compose_file" down || true
  fi

  if [ -f "${backup_dir}/.env" ]; then
    cp "${backup_dir}/.env" "${app_dir}/.env"
  fi

  if [ -f "${backup_dir}/data.tar.gz" ]; then
    echo "  restoring data/ ..."
    rm -rf "${app_dir}/data"
    tar xzf "${backup_dir}/data.tar.gz" -C "$app_dir"
  fi

  local f vol_short vol_full
  for f in "${backup_dir}"/volume__*.tar; do
    [ -e "$f" ] || continue
    vol_short=$(basename "$f" .tar | sed 's/^volume__//')
    vol_full="${project}_${vol_short}"
    echo "  restoring volume ${vol_full} ..."
    podman volume exists "$vol_full" 2>/dev/null && podman volume rm -f "$vol_full" >/dev/null
    podman volume create "$vol_full" >/dev/null
    podman volume import "$vol_full" "$f"
  done

  if [ -f "$compose_file" ]; then
    echo "  starting ${app_id}..."
    podman-compose -f "$compose_file" up -d
  fi
}

# Snapshots the current image ID used by each running container of an
# app's compose project. Prints "<service> <image-id>" lines, consumed by
# rollback_image_ids later.
snapshot_image_ids() {
  local app_id="$1" project; project=$(_project_name_for "$app_id")
  podman ps -a --filter "label=io.podman.compose.project=${project}" \
    --format '{{.Names}} {{.Image}}' 2>/dev/null | while read -r name image; do
    printf '%s %s\n' "$name" "$(podman inspect --format '{{.Image}}' "$name" 2>/dev/null)"
  done
}

# Re-tags each snapshotted image ID back onto the image:tag it originally
# came from, so the next `up -d --force-recreate` recreates containers
# from the pre-update image instead of the newly pulled one.
# Usage: rollback_image_ids "$snapshot"   (snapshot = output of snapshot_image_ids)
rollback_image_ids() {
  local snapshot="$1"
  [ -z "$snapshot" ] && return 0
  local name old_image_id current_ref
  while read -r name old_image_id; do
    [ -z "$name" ] && continue
    current_ref=$(podman inspect --format '{{.ImageName}}' "$name" 2>/dev/null || true)
    if [ -n "$current_ref" ] && [ -n "$old_image_id" ]; then
      echo "  retagging ${current_ref} -> ${old_image_id}"
      podman tag "$old_image_id" "$current_ref" 2>/dev/null || true
    fi
  done <<< "$snapshot"
}

# Waits a few seconds, then checks that every container in the app's
# compose project is in "running" state. Returns non-zero if any
# container is missing/exited/restarting.
app_containers_healthy() {
  local app_id="$1" wait_secs="${2:-5}" project; project=$(_project_name_for "$app_id")
  sleep "$wait_secs"
  local states
  states=$(podman ps -a --filter "label=io.podman.compose.project=${project}" --format '{{.State}}')
  if [ -z "$states" ]; then
    echo "  no containers found for ${app_id}" >&2
    return 1
  fi
  local s
  while read -r s; do
    if [ "$s" != "running" ]; then
      echo "  container state '${s}' is not healthy" >&2
      return 1
    fi
  done <<< "$states"
  return 0
}

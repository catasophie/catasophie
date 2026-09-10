#!/usr/bin/env bash
# Shared helpers sourced by root and per-app install/update scripts.
# Not meant to be executed directly.

CATASOPHIE_ROOT="${CATASOPHIE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
INSTALLED_MARKER_FILE="${CATASOPHIE_ROOT}/.installed"

# Fails with a clear message if required tools aren't on PATH, or if the
# running bash is too old. These scripts use bash 4+ features (mapfile,
# associative arrays). macOS ships bash 3.2 by default (a licensing
# artifact, not a capability limit) - on macOS, install a newer bash via
# `brew install bash` and either put it ahead of /bin/bash on PATH, or
# invoke bash explicitly, e.g. `$(brew --prefix)/bin/bash apps/cli/scripts/install.sh`.
check_deps() {
  if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "error: bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} is too old (need bash 4+)." >&2
    if [ "$(uname -s)" = "Darwin" ]; then
      echo "  macOS ships bash 3.2 at /bin/bash. Install a newer one and re-run with it:" >&2
      echo "    brew install bash" >&2
      echo "    \$(brew --prefix)/bin/bash $0 $*" >&2
    else
      echo "  Install a newer bash (4+) via your distro's package manager." >&2
    fi
    exit 1
  fi

  local missing=()
  command -v podman >/dev/null 2>&1 || missing+=("podman")
  command -v podman-compose >/dev/null 2>&1 || missing+=("podman-compose")
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "error: missing required tool(s): ${missing[*]}" >&2
    echo "  Run 'make bootstrap' (or ./apps/cli/scripts/bootstrap.sh) to install them." >&2
    if [ "$(uname -s)" = "Darwin" ]; then
      echo "  Manually: brew install podman podman-compose && podman machine init && podman machine start" >&2
    else
      echo "  Manually: see https://podman.io/docs/installation and https://github.com/containers/podman-compose" >&2
    fi
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

# Sets VAR=value in env_file, updating the existing line in place if
# present, otherwise appending. Also exports VAR=value into the current
# shell, so callers don't need to re-source the whole env_file to see
# it (which would otherwise risk clobbering not-yet-prompted variables
# still blank in env_file with prompt_if_unset/prompt_choice_if_unset
# calls still to come). Shared by prompt_if_unset/prompt_choice_if_unset
# (and safe to call directly).
# Usage: set_env_var VAR_NAME "value" "path/to/.env"
set_env_var() {
  local var_name="$1" value="$2" env_file="$3"
  if grep -qE "^${var_name}=" "$env_file" 2>/dev/null; then
    sed -i.bak "s#^${var_name}=.*#${var_name}=${value}#" "$env_file" && rm -f "$env_file.bak"
  else
    echo "${var_name}=${value}" >> "$env_file"
  fi
  export "${var_name}=${value}"
}

# Reads VAR from env_file; if unset/empty, prompts interactively (showing
# a default if given) and appends/updates it in env_file. If VAR is
# already exported in the process environment (e.g. `VAR=x ./script.sh`),
# that value takes precedence over what's already in env_file and skips
# the prompt too - it's persisted into env_file so it's remembered next
# time as well.
# Usage: prompt_if_unset VAR_NAME "Prompt text" ["default value"] "path/to/.env"
prompt_if_unset() {
  local var_name="$1" prompt_text="$2" default_value="$3" env_file="$4"
  local current

  if [ -n "${!var_name:-}" ]; then
    set_env_var "$var_name" "${!var_name}" "$env_file"
    echo "  ${var_name}=${!var_name} (from environment, skipping prompt)"
    return 0
  fi

  current=$(grep -E "^${var_name}=" "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2-)

  if [ -n "$current" ]; then
    export "${var_name}=${current}"
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

  set_env_var "$var_name" "$answer" "$env_file"
}

# Reads VAR from env_file; if unset/empty, prompts interactively for a
# single choice from a space-separated list of options (default
# pre-selected). Uses a whiptail/dialog radiolist when available
# (falling back to it if the user cancels), otherwise a plain numbered
# prompt. No-op if VAR is already set - safe to re-run. If VAR is
# already exported in the process environment, that value takes
# precedence and skips the prompt too (see prompt_if_unset).
# Usage: prompt_choice_if_unset VAR_NAME "Prompt text" "opt1 opt2 opt3" "default_opt" "path/to/.env"
prompt_choice_if_unset() {
  local var_name="$1" prompt_text="$2" opts_str="$3" default_opt="$4" env_file="$5"
  local current

  if [ -n "${!var_name:-}" ]; then
    set_env_var "$var_name" "${!var_name}" "$env_file"
    echo "  ${var_name}=${!var_name} (from environment, skipping prompt)"
    return 0
  fi

  current=$(grep -E "^${var_name}=" "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2-)

  if [ -n "$current" ]; then
    export "${var_name}=${current}"
    echo "  ${var_name} already set (skipping prompt)"
    return 0
  fi

  local -a opts
  read -r -a opts <<< "$opts_str"
  local choice=""

  local tool=""
  if command -v whiptail >/dev/null 2>&1; then
    tool=whiptail
  elif command -v dialog >/dev/null 2>&1; then
    tool=dialog
  fi

  if [ -n "$tool" ]; then
    local args=(--radiolist "$prompt_text" 20 78 "${#opts[@]}")
    local opt status
    for opt in "${opts[@]}"; do
      status="OFF"
      [ "$opt" = "$default_opt" ] && status="ON"
      args+=("$opt" "$opt" "$status")
    done
    if ! choice=$("$tool" "${args[@]}" 3>&1 1>&2 2>&3); then
      echo "Cancelled - using default: ${default_opt}"
      choice="$default_opt"
    fi
  else
    echo "$prompt_text"
    local i=1 opt
    local -A idx_to_opt
    for opt in "${opts[@]}"; do
      local marker=""
      [ "$opt" = "$default_opt" ] && marker=" (default)"
      printf "  %d) %s%s\n" "$i" "$opt" "$marker"
      idx_to_opt[$i]="$opt"
      i=$((i + 1))
    done
    local answer
    read -r -p "Enter number [${default_opt}]: " answer
    if [ -z "$answer" ]; then
      choice="$default_opt"
    else
      choice="${idx_to_opt[$answer]:-$default_opt}"
    fi
  fi

  set_env_var "$var_name" "$choice" "$env_file"
  echo "  ${var_name}=${choice}"
}

# Reads VAR from env_file; if unset/empty, prompts interactively for
# zero or more choices (toggled on/off) from a space-separated list of
# options (default options pre-checked), storing the selection back as a
# space-separated string. Uses a whiptail/dialog checklist when
# available (falling back to it if the user cancels), otherwise a plain
# numbered prompt accepting a comma/space-separated list of numbers. If
# no tool is available and the user enters nothing, the default
# selection is kept. No-op if VAR is already set - safe to re-run. If
# VAR is already exported in the process environment, that value takes
# precedence and skips the prompt too (see prompt_if_unset).
# Usage: prompt_multi_choice_if_unset VAR_NAME "Prompt text" "opt1 opt2 opt3" "default_opt1 default_opt2" "path/to/.env"
prompt_multi_choice_if_unset() {
  local var_name="$1" prompt_text="$2" opts_str="$3" defaults_str="$4" env_file="$5"
  local current

  if [ -n "${!var_name:-}" ]; then
    set_env_var "$var_name" "${!var_name}" "$env_file"
    echo "  ${var_name}=${!var_name} (from environment, skipping prompt)"
    return 0
  fi

  current=$(grep -E "^${var_name}=" "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2-)

  if [ -n "$current" ]; then
    export "${var_name}=${current}"
    echo "  ${var_name} already set (skipping prompt)"
    return 0
  fi

  local -a opts defaults
  read -r -a opts <<< "$opts_str"
  read -r -a defaults <<< "$defaults_str"
  local is_default
  is_default() {
    local needle="$1" d
    for d in "${defaults[@]}"; do [ "$d" = "$needle" ] && return 0; done
    return 1
  }

  local choice=""
  local tool=""
  if command -v whiptail >/dev/null 2>&1; then
    tool=whiptail
  elif command -v dialog >/dev/null 2>&1; then
    tool=dialog
  fi

  if [ -n "$tool" ]; then
    local args=(--checklist "$prompt_text" 20 78 "${#opts[@]}")
    local opt status
    for opt in "${opts[@]}"; do
      status="OFF"
      is_default "$opt" && status="ON"
      args+=("$opt" "$opt" "$status")
    done
    local raw
    if raw=$("$tool" "${args[@]}" 3>&1 1>&2 2>&3); then
      # whiptail/dialog checklist output is space-separated,
      # double-quoted tokens, e.g. "\"opt1\" \"opt2\"" - strip the quotes.
      choice=$(echo "$raw" | tr -d '"')
    else
      echo "Cancelled - using default: ${defaults_str}"
      choice="$defaults_str"
    fi
  else
    echo "$prompt_text"
    local i=1 opt
    local -A idx_to_opt
    for opt in "${opts[@]}"; do
      local marker=""
      is_default "$opt" && marker=" (default)"
      printf "  %d) %s%s\n" "$i" "$opt" "$marker"
      idx_to_opt[$i]="$opt"
      i=$((i + 1))
    done
    local answer
    read -r -p "Enter number(s), comma/space-separated [${defaults_str}]: " answer
    if [ -z "$answer" ]; then
      choice="$defaults_str"
    else
      local -a picked=()
      local num
      for num in ${answer//,/ }; do
        [ -n "${idx_to_opt[$num]:-}" ] && picked+=("${idx_to_opt[$num]}")
      done
      if [ "${#picked[@]}" -eq 0 ]; then
        choice="$defaults_str"
      else
        choice="${picked[*]}"
      fi
    fi
  fi

  set_env_var "$var_name" "$choice" "$env_file"
  echo "  ${var_name}=${choice}"
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

mark_installed() {
  local app_id="$1"
  touch "$INSTALLED_MARKER_FILE"
  grep -qxF "$app_id" "$INSTALLED_MARKER_FILE" || echo "$app_id" >> "$INSTALLED_MARKER_FILE"
}

# Removes app_id from the installed marker file (used by uninstall.sh).
# No-op if the marker file doesn't exist or doesn't list it.
unmark_installed() {
  local app_id="$1"
  [ -f "$INSTALLED_MARKER_FILE" ] || return 0
  grep -vxF "$app_id" "$INSTALLED_MARKER_FILE" > "${INSTALLED_MARKER_FILE}.tmp" || true
  mv "${INSTALLED_MARKER_FILE}.tmp" "$INSTALLED_MARKER_FILE"
}

is_installed() {
  local app_id="$1"
  [ -f "$INSTALLED_MARKER_FILE" ] && grep -qxF "$app_id" "$INSTALLED_MARKER_FILE"
}

list_installed() {
  [ -f "$INSTALLED_MARKER_FILE" ] && cat "$INSTALLED_MARKER_FILE" || true
}

# Fine-grained progress tracking for multi-stage or externally-fallible
# install steps (e.g. "was this API key validated", "was file X already
# ingested") - complements mark_installed's whole-app granularity.
# Backed by apps/<id>/.install-steps (gitignored), one step-name per
# line, in the exact same style as the root .installed marker.
# Usage: mark_step_done <app-id> <step-name>
mark_step_done() {
  local app_id="$1" step="$2"
  local f; f="$(_app_dir_for "$app_id")/.install-steps"
  touch "$f"
  grep -qxF "$step" "$f" || echo "$step" >> "$f"
}

# Usage: step_done <app-id> <step-name> (exit status only, no output)
step_done() {
  local app_id="$1" step="$2"
  local f; f="$(_app_dir_for "$app_id")/.install-steps"
  [ -f "$f" ] && grep -qxF "$step" "$f"
}

# Usage: clear_step <app-id> <step-name> - e.g. to force a re-check/retry
clear_step() {
  local app_id="$1" step="$2"
  local f; f="$(_app_dir_for "$app_id")/.install-steps"
  [ -f "$f" ] || return 0
  grep -vxF "$step" "$f" > "$f.tmp" || true
  mv "$f.tmp" "$f"
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
# Backups live in backups/<app-id>/<timestamp>/. Each backup dir may
# contain:
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
# in apps/<app_id>/docker-compose.yml.
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

# Returns the app's directory. Ids prefixed "external/<name>" (see
# apps/cli/scripts/lib/external.sh and docs/EXTERNAL_APPS.md) resolve
# under apps/external/<name> instead of apps/<name> - every other
# helper below (compose file, data dir, project name, backup/restore)
# is built on top of this, so external apps work with all of them with
# no further special-casing.
_app_dir_for() {
  local app_id="$1"
  if [[ "$app_id" == external/* ]]; then
    echo "${CATASOPHIE_ROOT}/apps/external/${app_id#external/}"
  else
    echo "${CATASOPHIE_ROOT}/apps/${app_id}"
  fi
}

# Returns the app's compose file path.
_compose_file_for() {
  local app_id="$1"
  echo "$(_app_dir_for "$app_id")/docker-compose.yml"
}

# Resolves the app's actual data directory: reads DATA_DIR from the
# app's .env if set (see ensure_data_dir/DATA_DIR convention - lets data
# live on an external drive), otherwise falls back to <app_dir>/data -
# mirroring the `${DATA_DIR:-./data}` default used in docker-compose.yml
# bind mounts.
_data_dir_for() {
  local app_id="$1"
  local app_dir; app_dir=$(_app_dir_for "$app_id")
  local env_file="${app_dir}/.env"
  local configured=""
  if [ -f "$env_file" ]; then
    configured=$(grep -E '^DATA_DIR=' "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
  fi
  if [ -n "$configured" ]; then
    echo "$configured"
  else
    echo "${app_dir}/data"
  fi
}

# Creates the given data directory if missing. If it's an absolute path
# (i.e. explicitly redirected via DATA_DIR, presumably to an external
# drive) whose parent doesn't already exist, refuses to create it - this
# avoids silently creating a stray folder on the boot disk if the
# external drive isn't mounted yet. Relative paths (the default, under
# the app dir) are always created outright.
ensure_data_dir() {
  local dir="$1"
  [ -d "$dir" ] && return 0
  case "$dir" in
    /*)
      local parent; parent=$(dirname "$dir")
      if [ ! -d "$parent" ]; then
        echo "error: DATA_DIR parent '${parent}' doesn't exist - is the external drive mounted?" >&2
        echo "  create the base folder on the drive first, then re-run this installer." >&2
        return 1
      fi
      ;;
  esac
  mkdir -p "$dir"
}

# True when podman talks to a remote/VM service rather than running
# containers natively on this host (always the case on macOS, where
# podman is a client for a `podman machine` VM).
podman_is_remote() {
  [ "$(podman info --format '{{.Host.ServiceIsRemote}}' 2>/dev/null)" = "true" ]
}

# Gives a bind-mounted data dir to the fixed non-root uid some images run
# as, so the container can actually write to it.
#
# Native rootless podman (Linux): the host dir is owned by the invoking
# user, which maps to root *inside* the container's user namespace, not
# to the image's uid - so it must be chowned via `podman unshare`.
#
# Remote podman (macOS `podman machine`): `podman unshare` is not
# supported by the remote client at all (it errors out - this used to
# make install.sh fail on macOS), and it isn't needed: the file sharing
# layer between host and VM already presents bind mounts as owned by the
# container's uid. Verified writable from inside the container without
# any chown, so this is a no-op there.
chown_data_dir() {
  local dir="$1" owner="$2"
  if podman_is_remote; then
    return 0
  fi
  podman unshare chown -R "$owner" "$dir"
}

# Counterpart to chown_data_dir: removes a data dir whose contents may be
# owned by a container uid the current user can't otherwise unlink.
remove_data_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  if podman_is_remote; then
    rm -rf "$dir"
  else
    podman unshare rm -rf "$dir"
  fi
}

# podman-compose's project name (used in container labels) defaults to
# the compose file's directory name - i.e. the app id itself for
# first-party apps, or just the trailing part for "external/<name>"
# ids (that directory is apps/external/<name>, not apps/external/<name>
# nested under a directory literally called "external/<name>").
_project_name_for() {
  local app_id="$1"
  if [[ "$app_id" == external/* ]]; then
    echo "${app_id#external/}"
  else
    echo "$app_id"
  fi
}

# Backs up one app's .env, data dir (wherever DATA_DIR currently points -
# see _data_dir_for), and named volumes into dest_dir.
# For offline-maps specifically, raw/ (the source OSM extract,
# re-downloadable via import-region.sh) is excluded to keep backups
# smaller/faster.
backup_app() {
  local app_id="$1" dest_dir="$2"
  local app_dir; app_dir=$(_app_dir_for "$app_id")
  local project; project=$(_project_name_for "$app_id")
  local data_dir; data_dir=$(_data_dir_for "$app_id")
  mkdir -p "$dest_dir"

  if [ -f "${app_dir}/.env" ]; then
    cp "${app_dir}/.env" "${dest_dir}/.env"
  fi

  if [ -d "$data_dir" ]; then
    echo "  backing up ${app_id} data (${data_dir}) ..."
    local tar_excludes=()
    if [ "$app_id" = "offline-maps" ]; then
      tar_excludes+=(--exclude="./raw")
    fi
    tar czf "${dest_dir}/data.tar.gz" "${tar_excludes[@]}" -C "$data_dir" .
  else
    echo "  warn: data dir '${data_dir}' not found for ${app_id} - is an external drive unmounted? skipping data backup" >&2
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

# Restores an app's .env, data dir, and named volumes from a backup
# dir, stopping/starting the app's containers around the restore. Set
# ASSUME_YES=1 to skip the confirmation prompt. Note: .env is restored
# first, so if DATA_DIR differs between the backup and the current
# .env, data is restored to wherever the *restored* .env's DATA_DIR
# points (external drive must already be mounted there).
restore_app() {
  local app_id="$1" backup_dir="$2"
  local app_dir; app_dir=$(_app_dir_for "$app_id")
  local compose_file; compose_file=$(_compose_file_for "$app_id")
  local project; project=$(_project_name_for "$app_id")

  if [ ! -d "$backup_dir" ]; then
    echo "error: backup dir not found: $backup_dir" >&2
    return 1
  fi

  local data_dir; data_dir=$(_data_dir_for "$app_id")

  if [ "${ASSUME_YES:-0}" != "1" ]; then
    echo "About to restore ${app_id} from ${backup_dir}:"
    [ -f "${backup_dir}/.env" ] && echo "  - .env will be overwritten"
    [ -f "${backup_dir}/data.tar.gz" ] && echo "  - ${data_dir}/ will be replaced"
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
    # DATA_DIR may have changed in the restored .env - re-resolve.
    data_dir=$(_data_dir_for "$app_id")
  fi

  if [ -f "${backup_dir}/data.tar.gz" ]; then
    echo "  restoring data (${data_dir}) ..."
    ensure_data_dir "$data_dir" || return 1
    rm -rf "${data_dir:?}"
    mkdir -p "$data_dir"
    tar xzf "${backup_dir}/data.tar.gz" -C "$data_dir"
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

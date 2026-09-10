#!/usr/bin/env bash
# Generic driver + review-gate for apps/external/<id> - third-party apps
# the user manually clones into apps/external/ (see
# apps/external/README.md and docs/EXTERNAL_APPS.md). Not meant to be
# executed directly - sourced alongside common.sh.
#
# Unlike apps/<id>, external apps are only required to ship
# docker-compose.yml + manifest.json; install.sh/uninstall.sh/up.sh/
# down.sh are optional. When present, they're used as-is (identical to
# a first-party app). When absent, the generic functions below drive
# podman-compose directly.
#
# Every external app is addressed as the id "external/<dirname>"
# everywhere else in this toolchain - common.sh's _app_dir_for/
# _compose_file_for/_project_name_for/_data_dir_for already know how to
# resolve that prefix, so install.sh/update.sh/backup.sh treat it as
# just another app id.

EXTERNAL_DIR="${CATASOPHIE_ROOT}/apps/external"

# Lists every "external/<id>" that meets the minimum contract: a
# manifest.json and a docker-compose.yml.
list_external_apps() {
  local dir
  [ -d "$EXTERNAL_DIR" ] || return 0
  for dir in "${EXTERNAL_DIR}"/*/; do
    [ -d "$dir" ] || continue
    local name; name=$(basename "$dir")
    [ -f "${dir}manifest.json" ] || continue
    [ -f "${dir}docker-compose.yml" ] || continue
    echo "external/${name}"
  done
}

# Files whose content matters for the review gate (whichever exist).
_external_review_targets() {
  local app_dir="$1" f
  for f in docker-compose.yml install.sh uninstall.sh up.sh down.sh .env.example; do
    [ -f "${app_dir}/${f}" ] && echo "${app_dir}/${f}"
  done
}

# sha256 over every review-relevant file's content (stable/sorted order)
# - changes whenever any of them changes, e.g. after a `git pull`.
_external_review_hash() {
  local app_dir="$1" f hashes=""
  while IFS= read -r f; do
    hashes+="$(sha256sum "$f" | awk '{print $1}')"
  done < <(_external_review_targets "$app_dir" | sort)
  echo -n "$hashes" | sha256sum | awk '{print $1}'
}

# True if apps/external/<id>'s reviewable files match the hash recorded
# the last time review_external_app ran for it.
external_is_reviewed() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")
  local review_file="${app_dir}/.reviewed"
  [ -f "$review_file" ] || return 1
  [ "$(cat "$review_file" 2>/dev/null)" = "$(_external_review_hash "$app_dir")" ]
}

# Blocks (with instructions) unless the app has already been reviewed at
# its *current* content hash - forces re-review whenever
# docker-compose.yml/install.sh/etc. change, not just on first install.
require_external_reviewed() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")
  if external_is_reviewed "$app_id"; then
    return 0
  fi
  echo "error: '${app_id}' has not been reviewed (or has changed since it was last reviewed)." >&2
  echo "  This is third-party content - it runs arbitrary containers (and shell" >&2
  echo "  scripts, if it ships any) with your user's podman privileges. Read through" >&2
  echo "  its files before trusting them:" >&2
  local f
  while IFS= read -r f; do
    echo "    - $f" >&2
  done < <(_external_review_targets "$app_dir")
  echo "  Then run: ./apps/cli/scripts/review-external.sh ${app_id#external/}" >&2
  return 1
}

# Interactive review: prints the reviewable files' contents and asks for
# explicit confirmation, then records the current content hash so
# require_external_reviewed passes until the next content change.
review_external_app() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")
  if [ ! -d "$app_dir" ]; then
    echo "error: ${app_dir} not found - did you 'git clone <repo> ${app_dir}'?" >&2
    return 1
  fi
  if [ ! -f "${app_dir}/manifest.json" ] || [ ! -f "${app_dir}/docker-compose.yml" ]; then
    echo "error: ${app_dir} is missing manifest.json and/or docker-compose.yml - not a valid external app." >&2
    return 1
  fi

  echo "== Reviewing ${app_id} =="
  echo "This is third-party content, not maintained by catasophie. It will run"
  echo "arbitrary containers (and shell scripts, if it ships any) with your user's"
  echo "podman privileges. The files below will run or take effect if you proceed:"
  echo
  local f
  while IFS= read -r f; do
    echo "----------------------------------------------------------------------"
    echo "-- $f"
    echo "----------------------------------------------------------------------"
    cat "$f"
    echo
  done < <(_external_review_targets "$app_dir")
  echo "----------------------------------------------------------------------"

  if ! confirm "I have read the above and trust this source - proceed?"; then
    echo "Aborted - not marked as reviewed." >&2
    return 1
  fi

  _external_review_hash "$app_dir" > "${app_dir}/.reviewed"
  echo "Marked ${app_id} as reviewed. Note: if these files change again (e.g. a"
  echo "future 'make update' pulls new commits), review will be required again."
}

# === Generic up/down/install/uninstall for external apps that don't ===
# === ship their own scripts. ===

external_up() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")
  if [ -x "${app_dir}/up.sh" ]; then
    ( cd "$app_dir" && ./up.sh )
  else
    ensure_env_file "$app_dir"
    podman-compose -f "${app_dir}/docker-compose.yml" up -d
  fi
}

external_down() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")
  if [ -x "${app_dir}/down.sh" ]; then
    ( cd "$app_dir" && ./down.sh )
  else
    podman-compose -f "${app_dir}/docker-compose.yml" down
  fi
}

# Warns (doesn't block) if the port this app's manifest declares looks
# already claimed by another app's .env - first-party apps coordinate
# default ports by convention; external ones can't be checked ahead of
# time. Best-effort: needs python3 to parse manifest.json; silently
# skipped if unavailable.
_external_check_port_collision() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")
  local manifest="${app_dir}/manifest.json"
  command -v python3 >/dev/null 2>&1 || return 0
  [ -f "$manifest" ] || return 0

  local env_var default_port
  env_var=$(python3 -c "import json,sys
m=json.load(open(sys.argv[1]))
print(m.get('port',{}).get('envVar',''))" "$manifest" 2>/dev/null) || return 0
  [ -n "$env_var" ] || return 0
  default_port=$(python3 -c "import json,sys
m=json.load(open(sys.argv[1]))
print(m.get('port',{}).get('default',''))" "$manifest" 2>/dev/null) || true

  local this_port=""
  if [ -f "${app_dir}/.env" ]; then
    this_port=$(grep -E "^${env_var}=" "${app_dir}/.env" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
  fi
  [ -n "$this_port" ] || this_port="$default_port"
  [ -n "$this_port" ] || return 0

  local other_dir other_id other_port
  for other_dir in "${CATASOPHIE_ROOT}"/apps/*/ "${CATASOPHIE_ROOT}"/apps/external/*/; do
    [ -d "$other_dir" ] || continue
    [ "${other_dir%/}" = "${app_dir}" ] && continue
    other_id=$(basename "$other_dir")
    [ "$other_id" = "external" ] && continue
    [ -f "${other_dir}.env" ] || continue
    while IFS='=' read -r key value; do
      [[ "$key" == *_PORT ]] || continue
      if [ "$value" = "$this_port" ]; then
        echo "warn: port ${this_port} (${env_var}) may already be used by '${other_id}' (${key}) - check both apps' .env." >&2
      fi
    done < "${other_dir}.env"
  done
}

# Installs an external app - blocks on require_external_reviewed first.
external_install() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")
  require_external_reviewed "$app_id" || return 1
  _external_check_port_collision "$app_id"

  if [ -x "${app_dir}/install.sh" ]; then
    ( cd "$app_dir" && ./install.sh )
  else
    ensure_env_file "$app_dir"
    local data_dir; data_dir=$(_data_dir_for "$app_id")
    ensure_data_dir "$data_dir" || return 1
    podman-compose -f "${app_dir}/docker-compose.yml" up -d
  fi
  mark_installed "$app_id"
}

# Uninstalls an external app. Accepts the same flags as first-party
# uninstall.sh: --yes --keep-data --keep-backups --with-images. Never
# removes the apps/external/<id> checkout itself (that's the user's git
# clone) - only containers/volumes/data/.env/backups.
external_uninstall() {
  local app_id="$1"; shift
  local app_dir; app_dir=$(_app_dir_for "$app_id")

  if [ -x "${app_dir}/uninstall.sh" ]; then
    ( cd "$app_dir" && ./uninstall.sh "$@" )
    unmark_installed "$app_id"
    return 0
  fi

  local assume_yes=0 keep_data=0 keep_backups=0 with_images=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      --yes) assume_yes=1 ;;
      --keep-data) keep_data=1 ;;
      --keep-backups) keep_backups=1 ;;
      --with-images) with_images=1 ;;
    esac
  done

  if [ "$assume_yes" != "1" ]; then
    echo "About to uninstall ${app_id}: stop+remove containers/volumes$( [ "$keep_data" = "1" ] || echo ", data" )."
    confirm "Continue?" || { echo "Aborted."; return 1; }
  fi

  local down_flags=(-v)
  [ "$with_images" = "1" ] && down_flags+=(--rmi all)
  if [ -f "${app_dir}/docker-compose.yml" ]; then
    podman-compose -f "${app_dir}/docker-compose.yml" down "${down_flags[@]}" || true
  fi

  if [ "$keep_data" != "1" ]; then
    local data_dir; data_dir=$(_data_dir_for "$app_id")
    remove_data_dir "$data_dir"
  fi
  if [ "$keep_backups" != "1" ]; then
    rm -rf "${CATASOPHIE_ROOT}/backups/${app_id}"
  fi
  rm -f "${app_dir}/.env" "${app_dir}/.install-steps" "${app_dir}/.reviewed"
  unmark_installed "$app_id"
}

# Updates one external app in place: git-pulls its checkout
# (fast-forward only - never force, never touches a dirty tree), and if
# the pull changed any review-relevant file, requires a fresh review
# before restarting instead of silently running new code.
#
# Return codes: 0 = updated (or nothing to pull) and restarted, 1 = hard
# failure (dirty tree / diverged / not a git checkout, nothing changed),
# 2 = pulled successfully but blocked on review - caller should treat
# this distinctly from a hard failure.
external_update() {
  local app_id="$1" app_dir; app_dir=$(_app_dir_for "$app_id")

  if [ -d "${app_dir}/.git" ]; then
    # Only tracked-file changes should block a pull - untracked files
    # like .env/.reviewed/.install-steps (which we or the user create
    # inside the checkout) are expected and shouldn't count as "dirty".
    if [ -n "$(git -C "$app_dir" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      echo "warn: ${app_id} has uncommitted local changes - skipping git pull, update it manually." >&2
      return 1
    fi
    echo "  git pull (${app_id})..."
    if ! git -C "$app_dir" pull --ff-only; then
      echo "warn: git pull failed for ${app_id} (diverged history?) - update it manually." >&2
      return 1
    fi
  else
    echo "  ${app_id} is not a git checkout - can't auto-update, just recreating containers." >&2
  fi

  if ! external_is_reviewed "$app_id"; then
    echo "warn: ${app_id}'s files changed and need re-review before restarting." >&2
    echo "  Run: ./apps/cli/scripts/review-external.sh $(basename "$app_dir")" >&2
    return 2
  fi

  if [ -f "${app_dir}/docker-compose.yml" ]; then
    podman-compose -f "${app_dir}/docker-compose.yml" pull || true
  fi
  external_up "$app_id"
}

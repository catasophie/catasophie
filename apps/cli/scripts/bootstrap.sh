#!/usr/bin/env bash
# Host bootstrap: installs the system-level dependencies these scripts
# and every app need (podman, podman-compose, make, git, bash 4+, ...),
# and sets up rootless podman's prerequisites (uidmap, subuid/subgid
# ranges). Run this once on a fresh host right after cloning the repo,
# before `make install`. Safe to re-run any time - every step is
# idempotent (skipped if already satisfied).
#
# Usage:
#   ./apps/cli/scripts/bootstrap.sh
#   make bootstrap
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "error: not running as root and 'sudo' isn't available - re-run as root or install sudo." >&2
    exit 1
  fi
fi

log() { echo "==> $*"; }

# === Linux: package-manager installs ===

install_pkgs_apt() {
  local pkgs=("$@")
  log "apt-get install: ${pkgs[*]}"
  $SUDO apt-get update -y
  $SUDO apt-get install -y "${pkgs[@]}"
}

install_pkgs_dnf() {
  local pkgs=("$@")
  log "dnf install: ${pkgs[*]}"
  $SUDO dnf install -y "${pkgs[@]}"
}

install_pkgs_yum() {
  local pkgs=("$@")
  log "yum install: ${pkgs[*]}"
  $SUDO yum install -y "${pkgs[@]}"
}

install_pkgs_pacman() {
  local pkgs=("$@")
  log "pacman -S: ${pkgs[*]}"
  $SUDO pacman -Sy --needed --noconfirm "${pkgs[@]}"
}

# Installs podman-compose from the package manager if available;
# otherwise falls back to pip3 --user (needed on distros - e.g. older
# Debian/Raspberry Pi OS - that don't package it, or package too old a
# version).
install_podman_compose_fallback() {
  if command -v podman-compose >/dev/null 2>&1; then
    return 0
  fi
  log "podman-compose not found via package manager - falling back to pip3 install --user podman-compose"
  if ! command -v pip3 >/dev/null 2>&1; then
    echo "error: pip3 not available to install podman-compose - install python3-pip and re-run." >&2
    return 1
  fi
  pip3 install --user podman-compose
  local user_base
  user_base=$(python3 -m site --user-base 2>/dev/null || true)
  if [ -n "$user_base" ] && [ -x "${user_base}/bin/podman-compose" ]; then
    echo "  note: podman-compose was installed to ${user_base}/bin - add it to PATH if not already:" >&2
    echo "    export PATH=\"${user_base}/bin:\$PATH\"" >&2
  fi
}

# Ensures the invoking (non-root) user has a subuid/subgid range
# allocated - required for rootless podman to create user namespaces.
# Most distros allocate one automatically on user creation via
# /etc/login.defs, but hosts where the user already existed before
# uidmap was installed (or minimal/container-based installs) can be
# missing it, causing confusing "newuidmap: ... not allowed" failures.
ensure_subuid_subgid() {
  [ "$(id -u)" -eq 0 ] && return 0
  local user; user="$(id -un)"

  if grep -qE "^${user}:" /etc/subuid 2>/dev/null && grep -qE "^${user}:" /etc/subgid 2>/dev/null; then
    log "subuid/subgid range already present for ${user}"
    return 0
  fi

  if ! command -v usermod >/dev/null 2>&1; then
    echo "warn: usermod not found - can't verify/add subuid/subgid range for ${user}." >&2
    echo "  rootless podman needs an entry in /etc/subuid and /etc/subgid - see:" >&2
    echo "  https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md" >&2
    return 0
  fi

  log "adding subuid/subgid range for ${user} (required for rootless podman)"
  $SUDO usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$user"
  echo "  note: log out and back in (or reboot) for the new subuid/subgid range to take effect." >&2
}

bootstrap_linux() {
  local id="" id_like=""
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  local family=""
  case "$id $id_like" in
    *debian*|*ubuntu*) family="debian" ;;
    *rhel*|*fedora*|*centos*) family="rhel" ;;
    *arch*) family="arch" ;;
    *)
      case "$id" in
        debian|ubuntu|raspbian) family="debian" ;;
        fedora|rhel|centos|rocky|almalinux) family="rhel" ;;
        arch|manjaro) family="arch" ;;
      esac
      ;;
  esac

  case "$family" in
    debian)
      local pkgs=(make git curl tar whiptail uidmap slirp4netns)
      command -v podman >/dev/null 2>&1 || pkgs+=(podman)
      command -v podman-compose >/dev/null 2>&1 || pkgs+=(podman-compose)
      install_pkgs_apt "${pkgs[@]}"
      install_podman_compose_fallback
      ;;
    rhel)
      local pkgs=(make git curl tar newt shadow-utils slirp4netns)
      command -v podman >/dev/null 2>&1 || pkgs+=(podman)
      command -v podman-compose >/dev/null 2>&1 || pkgs+=(podman-compose)
      if command -v dnf >/dev/null 2>&1; then
        install_pkgs_dnf "${pkgs[@]}"
      else
        install_pkgs_yum "${pkgs[@]}"
      fi
      install_podman_compose_fallback
      ;;
    arch)
      local pkgs=(make git curl tar libnewt shadow slirp4netns)
      command -v podman >/dev/null 2>&1 || pkgs+=(podman)
      command -v podman-compose >/dev/null 2>&1 || pkgs+=(podman-compose)
      install_pkgs_pacman "${pkgs[@]}"
      install_podman_compose_fallback
      ;;
    *)
      echo "error: unsupported/undetected Linux distro (ID='${id}', ID_LIKE='${id_like}')." >&2
      echo "  Install manually: podman, podman-compose, make, git - see https://podman.io/docs/installation" >&2
      exit 1
      ;;
  esac

  ensure_subuid_subgid
}

# === macOS: Homebrew ===

bootstrap_macos() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew not found - install it first: https://brew.sh" >&2
    exit 1
  fi

  local pkgs=(make git bash)
  command -v podman >/dev/null 2>&1 || pkgs+=(podman)
  command -v podman-compose >/dev/null 2>&1 || pkgs+=(podman-compose)

  log "brew install: ${pkgs[*]}"
  brew install "${pkgs[@]}"

  if podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
    log "podman machine already initialized"
  else
    log "podman machine init"
    podman machine init
  fi

  if podman machine list --format '{{.Name}} {{.Running}}' 2>/dev/null | grep -q ' true$'; then
    log "podman machine already running"
  else
    log "podman machine start"
    podman machine start
  fi

  echo
  echo "note: macOS ships bash 3.2 at /bin/bash, which these scripts can't use" >&2
  echo "  (need bash 4+). Homebrew's bash was just installed - either put it" >&2
  echo "  ahead of /bin/bash on PATH, or invoke scripts with it explicitly:" >&2
  echo "    \$(brew --prefix)/bin/bash apps/cli/scripts/install.sh" >&2
}

case "$(uname -s)" in
  Linux) bootstrap_linux ;;
  Darwin) bootstrap_macos ;;
  *)
    echo "error: unsupported OS '$(uname -s)' - install podman, podman-compose, make, and git manually." >&2
    echo "  See https://podman.io/docs/installation" >&2
    exit 1
    ;;
esac

echo
log "Host dependencies ready."
echo "  podman:         $(command -v podman || echo 'not found')"
echo "  podman-compose: $(command -v podman-compose || echo 'not found')"
echo "  make:           $(command -v make || echo 'not found')"
echo "  git:            $(command -v git || echo 'not found')"
echo
echo "Next: make install"

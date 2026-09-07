#!/usr/bin/env bash
# Main installer entrypoint. Idempotent - safe to re-run.
set -euo pipefail

cd "$(dirname "$0")"

echo "=== catasophie installer ==="

if ! command -v podman >/dev/null 2>&1; then
  echo "Podman is not installed. Please install Podman first (https://podman.io/docs/installation)." >&2
  exit 1
fi

if ! command -v podman-compose >/dev/null 2>&1; then
  echo "podman-compose not found. Please install it (e.g. 'brew install podman-compose' or 'pip install podman-compose')." >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "==> Creating .env from .env.example..."
  cp .env.example .env
else
  echo "==> .env already exists, leaving it untouched."
fi

REPO_ROOT="$(pwd)"
PODMAN_SOCK_PATH="$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null | sed 's#^unix://##')"
if [ -z "$PODMAN_SOCK_PATH" ]; then
  echo "Could not determine the Podman API socket path from 'podman info'." >&2
  exit 1
fi

echo "==> Setting CATASOPHIE_ROOT=${REPO_ROOT} in .env..."
if grep -q '^CATASOPHIE_ROOT=' .env; then
  # portable in-place edit (macOS/BSD sed vs GNU sed both handled)
  tmpfile="$(mktemp)"
  sed "s#^CATASOPHIE_ROOT=.*#CATASOPHIE_ROOT=${REPO_ROOT}#" .env > "$tmpfile" && mv "$tmpfile" .env
else
  echo "CATASOPHIE_ROOT=${REPO_ROOT}" >> .env
fi

echo "==> Setting PODMAN_SOCK=${PODMAN_SOCK_PATH} in .env..."
if grep -q '^PODMAN_SOCK=' .env; then
  tmpfile="$(mktemp)"
  sed "s#^PODMAN_SOCK=.*#PODMAN_SOCK=${PODMAN_SOCK_PATH}#" .env > "$tmpfile" && mv "$tmpfile" .env
else
  echo "PODMAN_SOCK=${PODMAN_SOCK_PATH}" >> .env
fi

echo "==> Ensuring the Podman API socket is enabled (needed for the dashboard to manage tools)..."
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user enable --now podman.socket 2>/dev/null || \
    echo "    (could not enable podman.socket via systemctl --user - ensure it's running manually, e.g. via 'podman machine' on macOS)"
else
  echo "    systemctl not available (likely macOS) - relying on 'podman machine' for the API socket."
fi

echo "==> Ensuring the shared 'catasophie' Podman network exists..."
podman network inspect catasophie >/dev/null 2>&1 || podman network create catasophie

echo "==> Pulling/building core services (proxy, auth, dashboard)..."
podman-compose up -d --build

echo ""
echo "=== Install complete ==="
echo "Open https://localhost/ (or https://<this-device-ip>/) to run the first-boot setup wizard."
echo "(You'll see a one-time certificate warning - this device uses a locally-generated cert, no internet needed.)"
echo ""
echo "Optional next steps:"
echo "  - WiFi hotspot: after completing setup, run 'sudo ./scripts/setup-wifi-ap.sh'"
echo "  - Health check: './scripts/doctor.sh'"
echo "  - Backups:      './scripts/backup.sh'"

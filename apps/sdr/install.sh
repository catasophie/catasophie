#!/usr/bin/env bash
# Interactive installer for sdr. Idempotent - safe to re-run.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

echo "== sdr install =="
check_deps
ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"

prompt_if_unset DATA_DIR \
  "Directory for persistent data (blank = ./data here, or an absolute path e.g. an external drive mount)" \
  "" "$ENV_FILE"

prompt_if_unset SDR_PORT \
  "Port to publish sdr on (http://localhost:<port>/)" \
  "3040" "$ENV_FILE"

prompt_if_unset TZ \
  "Timezone for the container (e.g. America/New_York)" \
  "UTC" "$ENV_FILE"

prompt_if_unset OPENWEBRX_ADMIN_USER \
  "Admin username for the OpenWebRX+ web UI" \
  "admin" "$ENV_FILE"

# Note: this is a plain read prompt (echoed to the terminal, stored as
# plaintext in .env) like every other setting in this repo - acceptable
# given ARCHITECTURE.md's trusted-LAN-only threat model, but don't reuse
# a sensitive password here.
prompt_if_unset OPENWEBRX_ADMIN_PASSWORD \
  "Admin password for the OpenWebRX+ web UI (used only to create the account on first boot)" \
  "" "$ENV_FILE"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
ensure_data_dir "$data_dir" || exit 1
mkdir -p "${data_dir}/var" "${data_dir}/etc"

cat <<'EOF'

=== RTL-SDR hardware prerequisites ===
Before this app can actually receive anything, on the HOST (not in a
container):
  1. Blacklist the kernel's own DVB driver, which otherwise claims the
     dongle before librtlsdr can (see README.md for the exact command).
  2. Make sure the dongle's USB device node is readable/writable by
     whichever user/group runs podman (a udev rule - see README.md).
Skip this if you already did it for a previous install.
=======================================

EOF

echo "Starting sdr..."
podman-compose -f "${APP_DIR}/docker-compose.yml" up -d

mark_installed sdr
echo "== sdr installed. Visit http://localhost:${SDR_PORT:-3040}/ =="
echo "   One-time manual step: log in with the admin account above at"
echo "   http://localhost:${SDR_PORT:-3040}/settings and add your RTL-SDR"
echo "   device + at least one frequency profile (Settings > SDR Devices"
echo "   and Profiles) - OpenWebRX has no supported way to pre-configure"
echo "   this from a file, so it can't be automated here."

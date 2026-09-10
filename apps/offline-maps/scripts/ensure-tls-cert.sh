#!/usr/bin/env bash
# Generates a self-signed TLS cert+key for the "web" service's HTTPS
# listener (see templates/nginx.conf), if not already present.
# Idempotent - safe to call on every install.sh/up.sh run (skips if
# both files already exist), and safe to re-run manually to force
# regeneration (delete the two files first).
#
# Why this exists at all: browsers only expose the Geolocation API
# (used for the "you are here" marker) on secure contexts - "localhost"
# is exempt, but LAN-IP access (the normal way to reach this app from
# another device) is not, so HTTPS is required for that to work at all
# - see templates/nginx.conf's top comment for the full picture
# (including why tiles requests are proxied through the same origin
# too). A self-signed cert is good enough here: the browser will show
# a one-time "not trusted" warning to click through, but the
# geolocation/secure-context behavior works identically to a
# CA-signed cert once accepted - there's no public DNS name to get a
# real one for anyway on a LAN-only device.
#
# The generated cert's SAN list includes "localhost"/127.0.0.1 plus
# every non-loopback IPv4 address currently configured on this host
# (best-effort - re-run this script, or just delete
# data/certs/web.{crt,key} and restart, if the device's LAN IP changes
# later and the browser starts complaining about a hostname mismatch).
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../../cli/scripts/lib/common.sh
source "${APP_DIR}/../cli/scripts/lib/common.sh"

ensure_env_file "$APP_DIR"
ENV_FILE="${APP_DIR}/.env"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

data_dir="${DATA_DIR:-${APP_DIR}/data}"
certs_dir="${data_dir}/certs"
crt="${certs_dir}/web.crt"
key="${certs_dir}/web.key"

if [ -f "$crt" ] && [ -f "$key" ]; then
  echo "TLS cert already present (${crt}) - skipping"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "error: openssl is required to generate the self-signed TLS cert for HTTPS (needed for geolocation to work over LAN)." >&2
  echo "  Install it via your distro's package manager (it's part of the base system on almost all Linux distros, including Raspberry Pi OS/Debian/Ubuntu) and re-run." >&2
  exit 1
fi

mkdir -p "$certs_dir"

# Best-effort list of this host's own non-loopback IPv4 addresses, so
# the cert's SAN matches whatever LAN IP a browser actually uses.
ips=()
if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
  # shellcheck disable=SC2207
  ips=($(hostname -I 2>/dev/null))
elif command -v ip >/dev/null 2>&1; then
  # shellcheck disable=SC2207
  ips=($(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1))
fi

san="DNS:localhost,IP:127.0.0.1"
for ip in "${ips[@]}"; do
  [ "$ip" = "127.0.0.1" ] && continue
  san="${san},IP:${ip}"
done

echo "Generating self-signed TLS cert (SAN: ${san})..."
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout "${key}.tmp" -out "${crt}.tmp" \
  -subj "/CN=catasophie-offline-maps" \
  -addext "subjectAltName=${san}" \
  >/dev/null 2>&1
mv "${key}.tmp" "$key"
mv "${crt}.tmp" "$crt"
chmod 600 "$key"

echo "TLS cert written to ${crt} (valid 10 years, self-signed - browsers will warn once, see README.md)"

#!/usr/bin/env bash
# Turns a Raspberry Pi's on-board (or USB) WiFi adapter into a local
# access point, so clients (phones, laptops, ...) can connect directly
# to the Pi and reach the apps it's serving, with no internet or
# existing router required. Uses NetworkManager (nmcli), which ships by
# default on Raspberry Pi OS (Bullseye and newer) and most current
# desktop Linux distros - no hostapd/dnsmasq setup needed.
#
# Idempotent: safe to re-run. Config (SSID/password/interface) is
# persisted to apps/cli/scripts/.hotspot.env and reused on subsequent
# runs/reboots. Existing WiFi client connections on the same interface
# are left untouched in NetworkManager (just not active while the
# hotspot connection is up) - use hotspot-down.sh to tear the hotspot
# down and optionally reconnect to a saved WiFi network instead.
#
# Usage:
#   ./apps/cli/scripts/hotspot-up.sh
#   make hotspot-up
#
# Env overrides (skip prompts, e.g. for non-interactive/scripted use):
#   HOTSPOT_IFACE=wlan0 HOTSPOT_SSID=catasophie HOTSPOT_PASSWORD=... \
#     ./apps/cli/scripts/hotspot-up.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=lib/common.sh
source apps/cli/scripts/lib/common.sh

CONN_NAME="catasophie-hotspot"
HOTSPOT_ENV_FILE="apps/cli/scripts/.hotspot.env"
touch "$HOTSPOT_ENV_FILE"

if ! command -v nmcli >/dev/null 2>&1; then
  echo "error: nmcli (NetworkManager) not found." >&2
  echo "  Raspberry Pi OS (Bullseye+) ships it by default. Install with:" >&2
  echo "    sudo apt-get install -y network-manager" >&2
  echo "  and make sure it's the active network backend (not dhcpcd), then re-run." >&2
  exit 1
fi

if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
  echo "error: NetworkManager service isn't running." >&2
  echo "  sudo systemctl enable --now NetworkManager" >&2
  exit 1
fi

# Discover WiFi interfaces (radio devices of type "wifi").
mapfile -t WIFI_IFACES < <(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1}')
if [ "${#WIFI_IFACES[@]}" -eq 0 ]; then
  echo "error: no WiFi interface found - is a WiFi adapter present and enabled?" >&2
  echo "  Check 'nmcli device status' and 'rfkill list' (unblock with 'rfkill unblock wifi')." >&2
  exit 1
fi

if [ -n "${HOTSPOT_IFACE:-}" ]; then
  set_env_var HOTSPOT_IFACE "$HOTSPOT_IFACE" "$HOTSPOT_ENV_FILE"
elif [ "${#WIFI_IFACES[@]}" -eq 1 ]; then
  set_env_var HOTSPOT_IFACE "${WIFI_IFACES[0]}" "$HOTSPOT_ENV_FILE"
  echo "  HOTSPOT_IFACE=${WIFI_IFACES[0]} (only WiFi interface found)"
else
  prompt_choice_if_unset HOTSPOT_IFACE "Which WiFi interface should host the hotspot?" \
    "${WIFI_IFACES[*]}" "${WIFI_IFACES[0]}" "$HOTSPOT_ENV_FILE"
fi

prompt_if_unset HOTSPOT_SSID "Hotspot network name (SSID)" "catasophie" "$HOTSPOT_ENV_FILE"

if [ -z "${HOTSPOT_PASSWORD:-}" ]; then
  current_pw=$(grep -E '^HOTSPOT_PASSWORD=' "$HOTSPOT_ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
  if [ -n "$current_pw" ]; then
    export HOTSPOT_PASSWORD="$current_pw"
    echo "  HOTSPOT_PASSWORD already set (skipping prompt)"
  else
    read -r -s -p "Hotspot password (min 8 chars, blank = open/no password): " HOTSPOT_PASSWORD
    echo
  fi
fi
if [ -n "$HOTSPOT_PASSWORD" ] && [ "${#HOTSPOT_PASSWORD}" -lt 8 ]; then
  echo "error: WPA2 passwords must be at least 8 characters." >&2
  exit 1
fi
set_env_var HOTSPOT_PASSWORD "$HOTSPOT_PASSWORD" "$HOTSPOT_ENV_FILE"

prompt_if_unset HOTSPOT_IP_CIDR "Hotspot IP address for this Pi (CIDR)" "10.42.0.1/24" "$HOTSPOT_ENV_FILE"
HOTSPOT_IP="${HOTSPOT_IP_CIDR%/*}"

log() { echo "==> $*"; }

if nmcli -t -f NAME connection show | grep -qxF "$CONN_NAME"; then
  log "updating existing hotspot connection profile '${CONN_NAME}'"
  nmcli connection modify "$CONN_NAME" \
    connection.interface-name "$HOTSPOT_IFACE" \
    802-11-wireless.ssid "$HOTSPOT_SSID" \
    ipv4.addresses "$HOTSPOT_IP_CIDR"
else
  log "creating hotspot connection profile '${CONN_NAME}' on ${HOTSPOT_IFACE}"
  nmcli connection add type wifi ifname "$HOTSPOT_IFACE" con-name "$CONN_NAME" autoconnect no ssid "$HOTSPOT_SSID"
  nmcli connection modify "$CONN_NAME" \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    ipv4.method shared \
    ipv4.addresses "$HOTSPOT_IP_CIDR"
fi

if [ -n "$HOTSPOT_PASSWORD" ]; then
  nmcli connection modify "$CONN_NAME" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$HOTSPOT_PASSWORD"
else
  log "warning: no password set - hotspot will be open (unencrypted)"
  nmcli connection modify "$CONN_NAME" wifi-sec.key-mgmt none 2>/dev/null || true
fi

log "bringing up '${CONN_NAME}' on ${HOTSPOT_IFACE}"
nmcli connection up "$CONN_NAME"

echo
log "Hotspot is up."
echo "  SSID:      ${HOTSPOT_SSID}"
if [ -n "$HOTSPOT_PASSWORD" ]; then
  echo "  Password:  ${HOTSPOT_PASSWORD}"
else
  echo "  Password:  (none - open network)"
fi
echo "  Pi IP:     ${HOTSPOT_IP}"
echo
echo "Connect a device to '${HOTSPOT_SSID}', then reach installed apps at"
echo "  http://${HOTSPOT_IP}:<app-port>/ - see each app's README for its port."
echo
echo "Stop the hotspot with: ./apps/cli/scripts/hotspot-down.sh (or make hotspot-down)"

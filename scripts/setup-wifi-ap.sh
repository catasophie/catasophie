#!/usr/bin/env bash
# Configures the host as a WiFi access point using hostapd + dnsmasq, so
# phones/laptops can connect directly to this device when there's no other
# network available. Reads config from .env (WIFI_AP_*).
#
# This runs at the HOST level (not in a container) because it needs raw access
# to the wireless interface, which containers can't easily get.
#
# Usage: sudo ./scripts/setup-wifi-ap.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (it configures network interfaces)." >&2
  echo "Try: sudo ./scripts/setup-wifi-ap.sh" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo ".env not found. Run the first-boot setup wizard first (visit the dashboard)." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

if [ "${WIFI_AP_ENABLED:-false}" != "true" ]; then
  echo "WIFI_AP_ENABLED is not 'true' in .env - nothing to do."
  exit 0
fi

IFACE="${WIFI_AP_INTERFACE:-wlan0}"
SSID="${WIFI_AP_SSID:-catasophie}"
PASSWORD="${WIFI_AP_PASSWORD:-changeme123}"
COUNTRY="${WIFI_AP_COUNTRY_CODE:-US}"

if [ ${#PASSWORD} -lt 8 ]; then
  echo "WIFI_AP_PASSWORD must be at least 8 characters (WPA2 requirement)." >&2
  exit 1
fi

command -v hostapd >/dev/null 2>&1 || { echo "hostapd not installed. Install it first (apt install hostapd)." >&2; exit 1; }
command -v dnsmasq >/dev/null 2>&1 || { echo "dnsmasq not installed. Install it first (apt install dnsmasq)." >&2; exit 1; }

echo "==> Configuring static IP on ${IFACE}..."
cat > "/etc/systemd/network/${IFACE}.network" <<EOF
[Match]
Name=${IFACE}

[Network]
Address=10.42.0.1/24
DHCPServer=no
EOF

echo "==> Writing hostapd config..."
mkdir -p /etc/hostapd
cat > /etc/hostapd/hostapd.conf <<EOF
interface=${IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=7
country_code=${COUNTRY}
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=${PASSWORD}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd 2>/dev/null || true

echo "==> Writing dnsmasq config (DHCP + DNS on ${IFACE})..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/catasophie.conf <<EOF
interface=${IFACE}
dhcp-range=10.42.0.10,10.42.0.200,255.255.255.0,24h
# Captive-portal-ish redirect: resolve everything to the dashboard
address=/#/10.42.0.1
EOF

echo "==> Enabling and restarting services..."
systemctl unmask hostapd
systemctl enable hostapd dnsmasq
systemctl restart systemd-networkd || true
systemctl restart dnsmasq
systemctl restart hostapd

echo "==> WiFi AP '${SSID}' configured on ${IFACE}."
echo "    Connect to it and browse to http://10.42.0.1/ to reach the dashboard."

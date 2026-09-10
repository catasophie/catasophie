#!/usr/bin/env bash
# Stops the WiFi access point started by hotspot-up.sh, freeing the WiFi
# interface back up (e.g. to reconnect it as a normal client to an
# existing WiFi network). Idempotent - safe to re-run even if the
# hotspot isn't currently up.
#
# Usage:
#   ./apps/cli/scripts/hotspot-down.sh
#   make hotspot-down
#
# By default this only brings the hotspot connection down. Pass
# --remove to also delete the saved "catasophie-hotspot" NetworkManager
# profile entirely (you'll be prompted for SSID/password again next
# time you run hotspot-up.sh).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

CONN_NAME="catasophie-hotspot"
REMOVE=0
for arg in "$@"; do
  case "$arg" in
    --remove) REMOVE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if ! command -v nmcli >/dev/null 2>&1; then
  echo "error: nmcli (NetworkManager) not found - nothing to do." >&2
  exit 1
fi

if nmcli -t -f NAME connection show --active | grep -qxF "$CONN_NAME"; then
  echo "==> bringing down '${CONN_NAME}'"
  nmcli connection down "$CONN_NAME"
else
  echo "==> '${CONN_NAME}' is not currently active"
fi

if [ "$REMOVE" -eq 1 ]; then
  if nmcli -t -f NAME connection show | grep -qxF "$CONN_NAME"; then
    echo "==> removing saved connection profile '${CONN_NAME}'"
    nmcli connection delete "$CONN_NAME"
  fi
  rm -f apps/cli/scripts/.hotspot.env
fi

echo "Hotspot stopped."

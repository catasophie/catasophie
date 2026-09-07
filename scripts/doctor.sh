#!/usr/bin/env bash
# catasophie doctor - audits the whole install and reports OK/WARN/FAIL per check.
#
# Usage:
#   ./scripts/doctor.sh            human-readable report
#   ./scripts/doctor.sh --json     machine-readable report (for the dashboard)
set -euo pipefail

cd "$(dirname "$0")/.."

JSON_MODE=false
[ "${1:-}" = "--json" ] && JSON_MODE=true

# results is a list of "STATUS|check name|detail" lines
RESULTS=()
OVERALL_OK=true

record() {
  local status="$1" name="$2" detail="$3"
  RESULTS+=("${status}|${name}|${detail}")
  if [ "$status" = "FAIL" ]; then
    OVERALL_OK=false
  fi
}

# ---------------------------------------------------------------------------
# Podman
# ---------------------------------------------------------------------------
if command -v podman >/dev/null 2>&1; then
  if podman info >/dev/null 2>&1; then
    record OK "Podman" "running"
  else
    record FAIL "Podman" "installed but not running/reachable (check 'podman machine start' on macOS, or the podman.socket service on Linux)"
  fi
  if command -v podman-compose >/dev/null 2>&1; then
    record OK "podman-compose" "$(podman-compose version 2>/dev/null | head -1 || echo present)"
  else
    record FAIL "podman-compose" "not found"
  fi
else
  record FAIL "Podman" "not installed"
fi

# ---------------------------------------------------------------------------
# .env
# ---------------------------------------------------------------------------
if [ -f .env ]; then
  record OK ".env file" "present"
  # shellcheck disable=SC1091
  set -a; source .env; set +a

  REQUIRED_VARS=(AUTH_SESSION_SECRET AUTH_STORAGE_ENCRYPTION_KEY AUTH_JWT_SECRET HARDWARE_PROFILE)
  for var in "${REQUIRED_VARS[@]}"; do
    value="${!var:-}"
    if [ -z "$value" ] || [[ "$value" == changeme* ]]; then
      record WARN ".env: ${var}" "unset or still a placeholder value"
    else
      record OK ".env: ${var}" "set"
    fi
  done

  if [ "${SETUP_COMPLETE:-false}" != "true" ]; then
    record WARN "First-boot setup" "not completed yet - visit the dashboard to run the wizard"
  else
    record OK "First-boot setup" "completed"
  fi
else
  record FAIL ".env file" "missing - run ./install.sh first"
fi

# ---------------------------------------------------------------------------
# Tool manifests
# ---------------------------------------------------------------------------
if [ -d tools ]; then
  for tool_dir in tools/*/; do
    tool_id="$(basename "$tool_dir")"
    [ "$tool_id" = "_template" ] && continue
    manifest="${tool_dir}manifest.json"
    compose_file="${tool_dir}docker-compose.yml"

    if [ ! -f "$manifest" ]; then
      record FAIL "tool '${tool_id}' manifest" "missing manifest.json"
      continue
    fi
    if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$manifest" 2>/dev/null; then
      record FAIL "tool '${tool_id}' manifest" "invalid JSON"
      continue
    fi
    record OK "tool '${tool_id}' manifest" "valid JSON"

    if [ ! -f "$compose_file" ]; then
      record FAIL "tool '${tool_id}' compose file" "missing docker-compose.yml"
    else
      record OK "tool '${tool_id}' compose file" "present"
    fi

    # requires_host_device check
    devices=$(python3 -c "
import json
data = json.load(open('${manifest}'))
for d in data.get('requires_host_device', []):
    print(d)
" 2>/dev/null || true)
    if [ -n "$devices" ]; then
      while IFS= read -r device_path; do
        [ -z "$device_path" ] && continue
        if [ -e "$device_path" ]; then
          record OK "tool '${tool_id}' device ${device_path}" "present"
        else
          record WARN "tool '${tool_id}' device ${device_path}" "not found - tool will not function until connected"
        fi
      done <<< "$devices"
    fi

    # container running?
    if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
      running=$(podman-compose -f "$compose_file" ps --status running -q 2>/dev/null || true)
      if [ -n "$running" ]; then
        record OK "tool '${tool_id}' container" "running"
      else
        record WARN "tool '${tool_id}' container" "not running (may be intentionally lazy-started)"
      fi
    fi

    # tool-provided healthcheck
    healthcheck="${tool_dir}healthcheck.sh"
    if [ -x "$healthcheck" ]; then
      if output=$(bash "$healthcheck" 2>&1); then
        record OK "tool '${tool_id}' healthcheck" "${output}"
      else
        record WARN "tool '${tool_id}' healthcheck" "${output}"
      fi
    fi
  done
else
  record WARN "tools directory" "not found"
fi

# ---------------------------------------------------------------------------
# WiFi AP (if enabled)
# ---------------------------------------------------------------------------
if [ "${WIFI_AP_ENABLED:-false}" = "true" ]; then
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet hostapd 2>/dev/null; then
      record OK "WiFi AP (hostapd)" "active"
    else
      record FAIL "WiFi AP (hostapd)" "enabled in .env but service not active - run sudo ./scripts/setup-wifi-ap.sh"
    fi
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
      record OK "WiFi AP (dnsmasq)" "active"
    else
      record FAIL "WiFi AP (dnsmasq)" "enabled in .env but service not active"
    fi
  else
    record WARN "WiFi AP" "systemctl not available on this host (not Linux?) - cannot verify"
  fi
fi

# ---------------------------------------------------------------------------
# Power monitor
# ---------------------------------------------------------------------------
POWER_BACKEND_VAL="${POWER_BACKEND:-auto}"
case "$POWER_BACKEND_VAL" in
  laptop)
    if [ -d /sys/class/power_supply ] && ls /sys/class/power_supply | grep -qi bat; then
      record OK "Power monitor (laptop)" "battery detected"
    else
      record WARN "Power monitor (laptop)" "backend set but no battery found on this host"
    fi
    ;;
  nut)
    if command -v upsc >/dev/null 2>&1; then
      record OK "Power monitor (nut)" "upsc client installed"
    else
      record WARN "Power monitor (nut)" "backend set but 'upsc' (NUT client) not installed"
    fi
    ;;
  pi-i2c)
    record WARN "Power monitor (pi-i2c)" "driver not implemented yet - see docs/HARDWARE.md"
    ;;
  none|auto)
    record OK "Power monitor" "backend: ${POWER_BACKEND_VAL}"
    ;;
esac

# ---------------------------------------------------------------------------
# Disk space
# ---------------------------------------------------------------------------
DISK_USE_PCT=$(df -P . | awk 'NR==2 {gsub("%","",$5); print $5}')
if [ "${DISK_USE_PCT:-0}" -ge 90 ] 2>/dev/null; then
  record WARN "Disk space" "${DISK_USE_PCT}% used"
else
  record OK "Disk space" "${DISK_USE_PCT:-unknown}% used"
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [ "$JSON_MODE" = true ]; then
  printf '['
  first=true
  for line in "${RESULTS[@]}"; do
    IFS='|' read -r status name detail <<< "$line"
    $first || printf ','
    first=false
    printf '{"status":"%s","check":"%s","detail":"%s"}' \
      "$status" "${name//\"/\\\"}" "${detail//\"/\\\"}"
  done
  printf ']\n'
else
  echo ""
  echo "=== catasophie doctor report ==="
  for line in "${RESULTS[@]}"; do
    IFS='|' read -r status name detail <<< "$line"
    case "$status" in
      OK) symbol="[OK]  " ;;
      WARN) symbol="[WARN]" ;;
      FAIL) symbol="[FAIL]" ;;
      *) symbol="[??]  " ;;
    esac
    printf "%s %-40s %s\n" "$symbol" "$name" "$detail"
  done
  echo ""
  if [ "$OVERALL_OK" = true ]; then
    echo "Overall: OK (warnings may still need attention above)"
  else
    echo "Overall: FAIL - one or more critical checks failed"
  fi
fi

[ "$OVERALL_OK" = true ]

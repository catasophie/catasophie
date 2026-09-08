#!/usr/bin/env bash
# Root install wizard: lets you pick which app(s) to install, then runs
# each selected app's own install.sh (see docs/ADDING_AN_APP.md for the
# install.sh contract). Each app is fully independent and reachable
# directly on its own published port(s) - no shared proxy involved.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"

check_deps

mapfile -t apps < <(list_available_apps | sort)
if [ "${#apps[@]}" -eq 0 ]; then
  echo "No installable apps found under apps/ (each needs an install.sh)." >&2
  exit 1
fi

selected=()

pick_with_whiptail() {
  local tool="$1"
  local args=(--separate-output --checklist "Select app(s) to install (space to toggle, enter to confirm):" 20 78 "${#apps[@]}")
  local id status
  for id in "${apps[@]}"; do
    status="OFF"
    is_installed "$id" && status="ON"
    args+=("$id" "$id" "$status")
  done
  local out
  if ! out=$("$tool" "${args[@]}" 3>&1 1>&2 2>&3); then
    echo "Cancelled." >&2
    exit 1
  fi
  mapfile -t selected <<< "$out"
}

pick_plain() {
  echo "Available apps:"
  local i=1
  local -A idx_to_app
  for id in "${apps[@]}"; do
    local marker=" "
    is_installed "$id" && marker="*"
    printf "  %2d) [%s] %s\n" "$i" "$marker" "$id"
    idx_to_app[$i]="$id"
    i=$((i + 1))
  done
  echo "(* = already installed)"
  read -r -p "Enter numbers to install, space-separated (e.g. \"1 3\"): " -a picks
  for p in "${picks[@]}"; do
    [ -n "${idx_to_app[$p]:-}" ] && selected+=("${idx_to_app[$p]}")
  done
}

if command -v whiptail >/dev/null 2>&1; then
  pick_with_whiptail whiptail
elif command -v dialog >/dev/null 2>&1; then
  pick_with_whiptail dialog
else
  pick_plain
fi

if [ "${#selected[@]}" -eq 0 ]; then
  echo "Nothing selected, exiting."
  exit 0
fi

echo "Selected: ${selected[*]}"
echo

results=()
for id in "${selected[@]}"; do
  echo
  echo "=========================================="
  echo " Installing: $id"
  echo "=========================================="
  if bash "apps/$id/install.sh"; then
    results+=("$id: OK")
  else
    results+=("$id: FAILED")
  fi
done

echo
echo "== Summary =="
for r in "${results[@]}"; do
  echo "  $r"
done
echo
echo "See each app's README for its port(s), or check its docker-compose.yml."

#!/usr/bin/env bash
# Scaffolds a new app by copying apps/_template/ to apps/<id>/ and
# substituting the id in the template files. See docs/ADDING_AN_APP.md.
# Interactively prompts for the app id and default port (no arguments
# needed).
# Usage: make add-app
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

id=""
while true; do
  read -r -p "App id (lowercase, digits, hyphens, e.g. radio-sdr): " id
  if [ -z "$id" ]; then
    echo "error: app id can't be empty" >&2
    continue
  fi
  if ! [[ "$id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "error: app id must be lowercase letters/digits, hyphen-separated (e.g. radio-sdr)" >&2
    continue
  fi
  if [ -e "apps/$id" ]; then
    echo "error: apps/$id already exists" >&2
    continue
  fi
  break
done
dest="apps/$id"

port=""
while true; do
  read -r -p "Default port to publish $id on (e.g. 3020): " port
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    break
  fi
  echo "error: port must be a number" >&2
done

# Env var names can't contain hyphens (app-ids can, e.g. "offline-maps") -
# derive a valid SCREAMING_SNAKE_CASE port variable name from the id.
port_var="$(echo "$id" | tr '[:lower:]-' '[:upper:]_')_PORT"

cp -r apps/_template "$dest"
# Portable in-place sed for both GNU and BSD sed
sed_i() { sed -i.bak "$@" && rm -f "${@: -1}.bak"; }

for f in "$dest"/docker-compose.yml "$dest"/README.md "$dest"/install.sh "$dest"/uninstall.sh "$dest"/up.sh "$dest"/down.sh "$dest"/.env.example; do
  sed -i.bak \
    -e "s#__APP_ID__#${id}#g" \
    -e "s#__PORT_VAR__#${port_var}#g" \
    -e "s#__PORT__#${port}#g" \
    "$f" && rm -f "$f.bak"
done
chmod +x "$dest"/install.sh "$dest"/uninstall.sh "$dest"/up.sh "$dest"/down.sh

echo "Created $dest. Next steps:"
echo "  1. Edit $dest/docker-compose.yml with your actual service(s)"
echo "  2. Edit $dest/install.sh (add any required config prompts)"
echo "  3. Edit $dest/README.md"
echo "  4. make install (or: $dest/install.sh)"

#!/usr/bin/env bash
# Scaffolds a new app by copying apps/_template/ to apps/<id>/ and
# substituting the id in the template files. See docs/ADDING_AN_APP.md.
# Usage: catasophie add-app <app-id> <default-port>
# Example: catasophie add-app radio-sdr 3020
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

id="${1:?usage: add-app.sh <app-id> <default-port>}"
port="${2:?usage: add-app.sh <app-id> <default-port>}"
dest="apps/$id"

if [ -e "$dest" ]; then
  echo "error: $dest already exists" >&2
  exit 1
fi

# Env var names can't contain hyphens (app-ids can, e.g. "offline-maps") -
# derive a valid SCREAMING_SNAKE_CASE port variable name from the id.
port_var="$(echo "$id" | tr '[:lower:]-' '[:upper:]_')_PORT"

cp -r apps/_template "$dest"
# Portable in-place sed for both GNU and BSD sed
sed_i() { sed -i.bak "$@" && rm -f "${@: -1}.bak"; }

for f in "$dest"/docker-compose.yml "$dest"/README.md "$dest"/install.sh "$dest"/uninstall.sh "$dest"/.env.example; do
  sed -i.bak \
    -e "s#__APP_ID__#${id}#g" \
    -e "s#__PORT_VAR__#${port_var}#g" \
    -e "s#__PORT__#${port}#g" \
    "$f" && rm -f "$f.bak"
done
chmod +x "$dest"/install.sh "$dest"/uninstall.sh

echo "Created $dest. Next steps:"
echo "  1. Edit $dest/docker-compose.yml with your actual service(s)"
echo "  2. Edit $dest/install.sh (add any required config prompts)"
echo "  3. Edit $dest/README.md"
echo "  4. catasophie install (or: $dest/install.sh)"

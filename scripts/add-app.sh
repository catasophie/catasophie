#!/usr/bin/env bash
# Scaffolds a new app by copying apps/_template/ to apps/<id>/ and
# substituting the id in the template files. See docs/ADDING_AN_APP.md.
# Usage: ./scripts/add-app.sh <app-id> <url-path> <internal-port>
# Example: ./scripts/add-app.sh radio-sdr /radio/ 8000
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

id="${1:?usage: add-app.sh <app-id> <url-path> <internal-port>}"
url_path="${2:?usage: add-app.sh <app-id> <url-path> <internal-port>}"
port="${3:?usage: add-app.sh <app-id> <url-path> <internal-port>}"
dest="apps/$id"

if [ -e "$dest" ]; then
  echo "error: $dest already exists" >&2
  exit 1
fi

cp -r apps/_template "$dest"
# Portable in-place sed for both GNU and BSD sed
sed_i() { sed -i.bak "$@" && rm -f "${@: -1}.bak"; }

for f in "$dest"/docker-compose.yml "$dest"/README.md; do
  sed -i.bak \
    -e "s#__APP_ID__#${id}#g" \
    -e "s#__URL_PATH__#${url_path}#g" \
    -e "s#__PORT__#${port}#g" \
    "$f" && rm -f "$f.bak"
done

echo "Created $dest. Next steps:"
echo "  1. Edit $dest/docker-compose.yml with your actual service(s)"
echo "  2. Edit $dest/README.md"
echo "  3. podman-compose -f $dest/docker-compose.yml up -d"

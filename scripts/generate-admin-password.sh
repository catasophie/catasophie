#!/usr/bin/env bash
# Generates a real Authelia argon2id password hash and writes it into
# core/auth/users_database.yml for the given user (default: admin).
#
# Usage: ./scripts/generate-admin-password.sh [username]
# You'll be prompted for the password interactively (not echoed).
set -euo pipefail

cd "$(dirname "$0")/.."

USERNAME="${1:-admin}"

read -rsp "New password for '${USERNAME}': " PASSWORD
echo

HASH=$(podman run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password "${PASSWORD}" 2>/dev/null \
  | grep -o 'Digest: .*' | sed 's/Digest: //')

if [ -z "${HASH}" ]; then
  echo "Failed to generate password hash. Is Podman running?" >&2
  exit 1
fi

python3 - "$USERNAME" "$HASH" <<'PYEOF'
import sys, re, pathlib
username, new_hash = sys.argv[1], sys.argv[2]
path = pathlib.Path("core/auth/users_database.yml")
text = path.read_text()
# naive replace of the password line under the target user block
pattern = re.compile(rf'(^\s*{re.escape(username)}:\n(?:^\s+.*\n)*?^\s+password:\s*).*$', re.MULTILINE)
def repl(m):
    return m.group(1) + f'"{new_hash}"'
new_text, count = pattern.subn(repl, text)
if count == 0:
    print(f"Could not find user '{username}' in users_database.yml", file=sys.stderr)
    sys.exit(1)
path.write_text(new_text)
print(f"Updated password hash for '{username}'.")
PYEOF

echo "Restart the auth service for the change to take effect:"
echo "  podman-compose restart auth"

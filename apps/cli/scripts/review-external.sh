#!/usr/bin/env bash
# Reviews a third-party app under apps/external/<id>: prints its
# reviewable files (docker-compose.yml + any install/uninstall/up/down
# scripts) and, on explicit confirmation, marks it as reviewed - a
# prerequisite before install/update will run its containers/scripts.
# See apps/external/README.md and docs/EXTERNAL_APPS.md.
#
# Re-review is required again any time those files change (e.g. after
# `make update` pulls new commits into it).
#
# Usage:
#   ./apps/cli/scripts/review-external.sh <id>
#   make review-external ARGS="<id>"
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
# shellcheck source=apps/cli/scripts/lib/common.sh
source "apps/cli/scripts/lib/common.sh"
# shellcheck source=apps/cli/scripts/lib/external.sh
source "apps/cli/scripts/lib/external.sh"

check_deps

id="${1:?usage: review-external.sh <id>  (the folder name under apps/external/)}"
review_external_app "external/${id}"

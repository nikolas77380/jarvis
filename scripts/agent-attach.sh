#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
ID=${1:-}
[ -n "$ID" ] || die "usage: agent-attach.sh <task-id>"
require_tools
META=$(require_meta "$ID")
herdr --session "$(meta_get "$META" session)" tab focus "$(meta_get "$META" tab)"

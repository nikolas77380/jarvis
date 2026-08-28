#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
ID=${1:-}
[ -n "$ID" ] || die "usage: agent-state.sh <task-id>"
require_tools
META=$(require_meta "$ID")
if [ "$(meta_get "$META" stopped)" = 1 ]; then
  echo 'state: stopped · source: metadata'
  exit 0
fi
STATUS=$(agent_status "$(meta_get "$META" agent_name)" "$(meta_get "$META" session)")
printf 'state: %s · source: herdr\n' "$STATUS"

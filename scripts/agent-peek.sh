#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
ID=${1:-}; LINES=${2:-80}
[ -n "$ID" ] || die "usage: agent-peek.sh <task-id> [lines]"
case "$LINES" in ''|*[!0-9]*|0) die "lines must be a positive integer" ;; esac
[ "$LINES" -le 500 ] || LINES=500
require_tools
META=$(require_meta "$ID")
herdr --session "$(meta_get "$META" session)" agent read "$(meta_get "$META" agent_name)" \
  --source recent-unwrapped --lines "$LINES"

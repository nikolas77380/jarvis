#!/usr/bin/env bash
# Read-only startup bearings: planned work plus live Herdr runtime state.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"

echo 'HARNESS SESSION START'
echo
echo 'ACTIVE PLAN CARDS'
if [ -f "$HARNESS_ROOT/plan/INDEX.md" ]; then
  grep -E '\| *(open|in-progress|in-review|blocked|needs-decision) *\|' "$HARNESS_ROOT/plan/INDEX.md" || echo '(none)'
else
  echo '(plan/INDEX.md not installed)'
fi
echo
echo 'HERDR AGENTS'
"$HARNESS_ROOT/scripts/agent-list.sh"

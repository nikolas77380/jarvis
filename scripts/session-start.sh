#!/usr/bin/env bash
# Recover durable attention, then show planned work and local runtime state.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"

echo 'HARNESS SESSION START'
if ! "$HARNESS_ROOT/scripts/events-poll.sh" >/dev/null; then echo 'warning: event poll failed' >&2; fi
echo
echo 'OPEN DECISIONS'
DECISIONS=$("$HARNESS_ROOT/scripts/decisions.sh" list)
if [ -n "$DECISIONS" ]; then printf '%s\n' "$DECISIONS"; else echo '(none)'; fi
echo
echo 'UNREAD EVENTS'
EVENTS=$("$HARNESS_ROOT/scripts/inbox.sh" list)
if [ -n "$EVENTS" ]; then printf '%s\n' "$EVENTS"; else echo '(none)'; fi
echo
echo 'ACTIVE PLAN CARDS'
if [ -f "$HARNESS_ROOT/plan/INDEX.md" ]; then
  grep -E '\| *(open|in-progress|in-review|blocked|needs-decision) *\|' "$HARNESS_ROOT/plan/INDEX.md" || echo '(none)'
else
  echo '(plan/INDEX.md not installed)'
fi
echo
echo 'FLEET STATE'
"$HARNESS_ROOT/scripts/fleet-snapshot.sh"

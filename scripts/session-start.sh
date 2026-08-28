#!/usr/bin/env bash
# Recover durable attention, then show planned work and local runtime state.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
PROJECT=''
if [ "$#" -gt 0 ]; then
  [ "$#" -eq 2 ] && [ "$1" = --project ] || die 'usage: session-start.sh [--project <name>]'
  PROJECT=$2
fi

echo 'HARNESS SESSION START'
if ! "$HARNESS_ROOT/scripts/events-poll.sh" >/dev/null; then echo 'warning: event poll failed' >&2; fi
echo
echo 'MEMORY CONTEXT'
if [ -n "$PROJECT" ]; then "$HARNESS_ROOT/scripts/memory-context.sh" --project "$PROJECT"; else "$HARNESS_ROOT/scripts/memory-context.sh"; fi
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

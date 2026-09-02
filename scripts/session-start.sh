#!/usr/bin/env bash
# Recover durable attention, then show planned work and local runtime state.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
PROJECT=''; NO_MEMORY=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || die 'usage: session-start.sh [--project <name>] [--no-memory]'; PROJECT=$2; shift 2 ;;
    --no-memory) NO_MEMORY=true; shift ;;
    *) die 'usage: session-start.sh [--project <name>] [--no-memory]' ;;
  esac
done

echo 'HARNESS SESSION START'
if ! "$HARNESS_ROOT/scripts/events-poll.sh" >/dev/null; then echo 'warning: event poll failed' >&2; fi
echo
if [ "$NO_MEMORY" = false ]; then
  echo 'MEMORY CONTEXT'
  if [ -n "$PROJECT" ]; then "$HARNESS_ROOT/scripts/memory-context.sh" --project "$PROJECT"; else "$HARNESS_ROOT/scripts/memory-context.sh"; fi
  echo
fi
echo 'OPEN DECISIONS'
DECISIONS=$("$HARNESS_ROOT/scripts/decisions.sh" list)
if [ -n "$DECISIONS" ]; then printf '%s\n' "$DECISIONS"; else echo '(none)'; fi
echo
echo 'UNREAD EVENTS'
EVENTS=$("$HARNESS_ROOT/scripts/inbox.sh" list)
if [ -n "$EVENTS" ]; then printf '%s\n' "$EVENTS"; else echo '(none)'; fi
echo
echo 'ACTIVE PLAN CARDS'
active_rows() { grep -E '\| *(open|in-progress|in-review|blocked|needs-decision) *\|' "$1" || true; }
if [ -n "$PROJECT" ]; then
  INDEX="$(project_root_path "$PROJECT")/plan/INDEX.md"
  if [ -f "$INDEX" ]; then
    ROWS=$(active_rows "$INDEX")
    [ -n "$ROWS" ] && printf '%s\n' "$ROWS" || echo '(none)'
  else
    echo "($PROJECT/plan/INDEX.md not installed)"
  fi
else
  FOUND=0
  ROOT_INDEX="$HARNESS_ROOT/plan/INDEX.md"
  if [ -f "$ROOT_INDEX" ]; then
    FOUND=1
    echo '-- jarvis --'
    ROWS=$(active_rows "$ROOT_INDEX")
    [ -n "$ROWS" ] && printf '%s\n' "$ROWS" || echo '(none)'
  fi
  for INDEX in "$HARNESS_ROOT"/projects/*/plan/INDEX.md; do
    [ -f "$INDEX" ] || continue
    FOUND=1
    echo "-- $(basename "$(dirname "$(dirname "$INDEX")")") --"
    ROWS=$(active_rows "$INDEX")
    [ -n "$ROWS" ] && printf '%s\n' "$ROWS" || echo '(none)'
  done
  [ "$FOUND" = 1 ] || echo '(no project plan/INDEX.md installed)'
fi
echo
echo 'FLEET STATE'
"$HARNESS_ROOT/scripts/fleet-snapshot.sh"

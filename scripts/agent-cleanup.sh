#!/usr/bin/env bash
# Close a settled specialist's exact Herdr tab. The ONLY trigger is the lead already having
# acknowledged the persisted agent-done event named by <event-id> — never detection, emission,
# unread listing, or drain alone, and never any other event type (blocked stays open; resume and
# quota flows reuse it in place).
#
# Immediately before closing, this re-reads the task's CURRENT metadata under its state lock and
# closes only if agent name, tab, session, and generation still match the identity the done event
# recorded at emit time. Any of those having moved (a newer spawn, switch, review handoff, or
# relaunch) makes cleanup a safe no-op that preserves the replacement tab. A close failure leaves
# the event's acknowledgement and the task's metadata untouched, is reported on stderr with a
# non-zero exit, and is safe to retry by re-running this same command.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
# shellcheck source=scripts/harness-event-lib.sh
. "$HARNESS_ROOT/scripts/harness-event-lib.sh"

EVENT_ID=${1:-}
[ -n "$EVENT_ID" ] || die "usage: agent-cleanup.sh <event-id>"
require_tools

EVENTS=$(event_file); ACKS=$(event_ack_file)
[ -f "$EVENTS" ] || die "no events recorded; nothing to clean up: $EVENT_ID"
EVENT=$(jq -c --arg id "$EVENT_ID" 'select(.id == $id)' "$EVENTS" | head -1)
[ -n "$EVENT" ] || die "event not found: $EVENT_ID"
TYPE=$(printf '%s' "$EVENT" | jq -r '.type')
[ "$TYPE" = agent-done ] || die "cleanup only applies to agent-done events; $EVENT_ID is $TYPE"
if [ ! -f "$ACKS" ] || ! jq -e --arg id "$EVENT_ID" 'select(.id == $id)' "$ACKS" >/dev/null 2>&1; then
  die "event is not acknowledged; acknowledge it first: $EVENT_ID"
fi

TASK=$(printf '%s' "$EVENT" | jq -r '.task')
valid_task_id "$TASK" || die "invalid task id in event: $TASK"
IDENTITY=$(printf '%s' "$EVENT" | jq -c '.identity // {}')
REC_AGENT=$(printf '%s' "$IDENTITY" | jq -r '.agentName // empty')
REC_TAB=$(printf '%s' "$IDENTITY" | jq -r '.tab // empty')
REC_SESSION=$(printf '%s' "$IDENTITY" | jq -r '.session // empty')
REC_GENERATION=$(printf '%s' "$IDENTITY" | jq -r '.generation // empty')
if [ -z "$REC_AGENT" ] || [ -z "$REC_TAB" ] || [ -z "$REC_SESSION" ] || [ -z "$REC_GENERATION" ]; then
  die "event carries no resolvable settled identity; cleanup refused: $EVENT_ID"
fi

state_lock_acquire "$TASK"
require_tools
META="$HARNESS_STATE/$TASK.meta"
if [ ! -f "$META" ] || [ -L "$META" ] || [ "$(meta_get "$META" schema)" != harness-herdr-task.v1 ]; then
  printf 'cleanup no-op: %s has no live runtime metadata\n' "$TASK"
  exit 0
fi
if [ "$(meta_get "$META" stopped)" = 1 ]; then
  printf 'cleanup no-op: %s already stopped\n' "$TASK"
  exit 0
fi
CUR_AGENT=$(meta_get "$META" agent_name)
CUR_TAB=$(meta_get "$META" tab)
CUR_SESSION=$(meta_get "$META" session)
CUR_GENERATION=$(meta_get "$META" generation); CUR_GENERATION=${CUR_GENERATION:-1}
if [ "$CUR_AGENT" != "$REC_AGENT" ] || [ "$CUR_TAB" != "$REC_TAB" ] \
  || [ "$CUR_SESSION" != "$REC_SESSION" ] || [ "$CUR_GENERATION" != "$REC_GENERATION" ]; then
  printf 'cleanup no-op: %s metadata moved past the settled generation (recorded g%s/%s, current g%s/%s); replacement tab preserved\n' \
    "$TASK" "$REC_GENERATION" "$REC_TAB" "$CUR_GENERATION" "$CUR_TAB"
  exit 0
fi
close_recorded_tab "$TASK" "$META"
printf 'cleaned up: %s · closed settled tab %s (generation %s)\n' "$TASK" "$CUR_TAB" "$CUR_GENERATION"

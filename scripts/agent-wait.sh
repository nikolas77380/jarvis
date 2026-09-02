#!/usr/bin/env bash
# Block until a dispatched task's agent settles (idle, done, or blocked).
#
# Why: the lead is a turn-based session — it only acts when it receives an input event, so a
# specialist reporting back in its own Herdr tab is otherwise invisible until the user happens to
# speak next. Run this in the background right after agent-spawn.sh/agent-switch.sh (Bash
# run_in_background): when it resolves, the harness's own background-completion notification wakes
# the lead up on its own, instead of only reacting once asked.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/quota-resume-lib.sh
. "$HARNESS_ROOT/scripts/quota-resume-lib.sh"

ID=${1:-}
TIMEOUT=''
if [ "$#" -gt 1 ]; then
  [ "$#" -eq 3 ] && [ "$2" = --timeout ] || die "usage: agent-wait.sh <task-id> [--timeout <ms>]"
  TIMEOUT=$3
fi
[ -n "$ID" ] || die "usage: agent-wait.sh <task-id> [--timeout <ms>]"
require_tools

META=$(require_meta "$ID")
[ "$(meta_get "$META" stopped)" != 1 ] || die "task $ID is stopped; nothing to wait for"
NAME=$(meta_get "$META" agent_name); SESSION=$(meta_get "$META" session)
[ -n "$NAME" ] && [ -n "$SESSION" ] || die "task $ID has no recorded agent"

ARGS=("$NAME")
[ -z "$TIMEOUT" ] || ARGS+=(--timeout "$TIMEOUT")
while :; do
  herdr --session "$SESSION" agent wait "${ARGS[@]}" >/dev/null
  STATE=$(agent_status "$NAME" "$SESSION")
  OUTPUT=$(herdr --session "$SESSION" agent read "$NAME" --source recent-unwrapped --lines 120 2>/dev/null || true)
  if printf '%s\n' "$OUTPUT" | quota_message_matches; then
    EPOCH=$(quota_resume_epoch "$OUTPUT") || die "task $ID hit a quota limit, but its reset time could not be parsed"
    quota_meta_write "$ID" task "$(meta_get "$META" engine)" "$EPOCH" "$OUTPUT" >/dev/null
    printf 'task %s quota-limited; automatic resume at %s\n' "$ID" "$(date -r "$EPOCH" 2>/dev/null || date -d "@$EPOCH")"
    while [ "$(date +%s)" -lt "$EPOCH" ]; do sleep 30; done
    "$HARNESS_ROOT/scripts/agent-switch.sh" "$ID" "$(meta_get "$META" engine)" --relaunch --note "Provider quota reset. Resume the task automatically from the preserved branch and worktree; do not wait for a human to say continue." >/dev/null
    quota_meta_remove "$ID"
    META=$(require_meta "$ID"); NAME=$(meta_get "$META" agent_name); SESSION=$(meta_get "$META" session)
    ARGS=("$NAME"); [ -z "$TIMEOUT" ] || ARGS+=(--timeout "$TIMEOUT")
    continue
  fi
  printf 'task %s settled: %s\n' "$ID" "$STATE"
  break
done

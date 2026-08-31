#!/usr/bin/env bash
# Compare durable fleet observations and append only actionable transitions.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
# shellcheck source=scripts/harness-event-lib.sh
. "$HARNESS_ROOT/scripts/harness-event-lib.sh"

[ "$#" -eq 0 ] || die 'usage: events-poll.sh'
"$HARNESS_ROOT/scripts/quota-resume-poll.sh"
CURRENT=$("$HARNESS_ROOT/scripts/fleet-snapshot.sh" --json)
printf '%s' "$CURRENT" | jq -e '.schema == "harness-fleet-snapshot.v1" and (.tasks|type=="array")' >/dev/null || die 'invalid fleet snapshot'
SNAPSHOT="$HARNESS_STATE/fleet-previous.json"
state_lock_acquire inbox
PREVIOUS='{"schema":"harness-fleet-snapshot.v1","tasks":[]}'
[ ! -f "$SNAPSHOT" ] || PREVIOUS=$(cat "$SNAPSHOT")

printf '%s' "$CURRENT" | jq -c '.tasks[]' | while IFS= read -r TASK_JSON; do
  TASK=$(printf '%s' "$TASK_JSON" | jq -r '.task')
  RUNTIME=$(printf '%s' "$TASK_JSON" | jq -r '.runtime.observed // "unknown"')
  CLEAN=$(printf '%s' "$TASK_JSON" | jq -r '.cleanSlate.state // "none"')
  HEAD=$(printf '%s' "$TASK_JSON" | jq -r '.worktree.head // "none"')
  OLD_RUNTIME=$(printf '%s' "$PREVIOUS" | jq -r --arg task "$TASK" '.tasks[]? | select(.task==$task) | .runtime.observed' | head -1)
  OLD_CLEAN=$(printf '%s' "$PREVIOUS" | jq -r --arg task "$TASK" '.tasks[]? | select(.task==$task) | .cleanSlate.state' | head -1)
  if [ "$RUNTIME" != "$OLD_RUNTIME" ]; then
    case "$RUNTIME" in
      done) event_emit "$TASK" agent-done "$RUNTIME-$HEAD" 'Agent completed' >/dev/null ;;
      blocked) event_emit "$TASK" agent-blocked "$RUNTIME-$HEAD" 'Agent is blocked' >/dev/null ;;
      missing) [ -z "$OLD_RUNTIME" ] || event_emit "$TASK" agent-missing "$RUNTIME-$HEAD" 'Recorded Herdr agent is missing' >/dev/null ;;
      archived) event_emit "$TASK" task-archived "$RUNTIME-$HEAD" 'Task worktree was archived' >/dev/null ;;
    esac
  fi
  if [ "$CLEAN" != "$OLD_CLEAN" ]; then
    case "$CLEAN" in
      awaiting-response) event_emit "$TASK" review-ready "$CLEAN-$HEAD" 'Review requires a response' >/dev/null ;;
      ready) event_emit "$TASK" ci-ready "$CLEAN-$HEAD" 'Validation and CI are ready' >/dev/null ;;
      failed) event_emit "$TASK" pipeline-failed "$CLEAN-$HEAD" 'Clean Slate failed' >/dev/null ;;
    esac
  fi
done
mkdir -p "$HARNESS_STATE"
TMP_SNAPSHOT=$(mktemp "$HARNESS_STATE/.fleet.XXXXXX")
printf '%s\n' "$CURRENT" > "$TMP_SNAPSHOT"; chmod 600 "$TMP_SNAPSHOT"; mv "$TMP_SNAPSHOT" "$SNAPSHOT"
state_lock_release

for META in "$HARNESS_STATE"/clean-slate/*.meta; do
  [ -f "$META" ] || continue
  [ "$(meta_get "$META" state)" = awaiting-response ] || continue
  TASK=$(meta_get "$META" task); ROUND=$(meta_get "$META" round); RESULT="$(meta_get "$META" run_dir)/review-$ROUND.json"
  [ -f "$RESULT" ] || continue
  jq -r '.findings[]? | select(.class=="needs-decision") | [.id,.message] | @tsv' "$RESULT" | while IFS=$'\t' read -r FINDING MESSAGE; do
    KEY=$(printf '%s-%s' "$TASK" "$FINDING" | tr -c 'a-zA-Z0-9._-' '_' | cut -c1-96)
    "$HARNESS_ROOT/scripts/decisions.sh" open "$TASK" --key "$KEY" --question "$MESSAGE" >/dev/null
  done
done
printf 'events-poll: ok\n'

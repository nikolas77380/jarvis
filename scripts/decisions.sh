#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
FILE="$HARNESS_STATE/decisions.jsonl"
mkdir -p "$HARNESS_STATE"; touch "$FILE"
open_json() { jq -s 'reduce .[] as $d ({}; .[$d.key] = $d) | [.[]] | map(select(.action == "opened"))' "$FILE"; }
COMMAND=${1:-list}; shift || true
case "$COMMAND" in
  list)
    [ "$#" -le 1 ] || die 'usage: decisions.sh list [--json]'
    JSON=$(open_json)
    if [ "${1:-}" = --json ]; then printf '%s\n' "$JSON"; else printf '%s\n' "$JSON" | jq -r '.[] | "\(.key) · \(.task) · \(.question)"'; fi
    ;;
  open)
    [ "$#" -eq 5 ] && [ "$2" = --key ] && [ "$4" = --question ] || die 'usage: decisions.sh open <task> --key <key> --question <text>'
    TASK=$1; KEY=$3; QUESTION=$5; valid_task_id "$TASK" || die "invalid task id: $TASK"; valid_task_id "$KEY" || die "invalid decision key: $KEY"
    state_lock_acquire decisions
    if ! open_json | jq -e --arg key "$KEY" '.[] | select(.key == $key)' >/dev/null; then
      jq -nc --arg task "$TASK" --arg key "$KEY" --arg question "$QUESTION" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '{schema:"harness-decision.v1",action:"opened",task:$task,key:$key,question:$question,createdAt:$at}' >> "$FILE"
    fi
    state_lock_release; printf 'opened: %s\n' "$KEY"
    ;;
  resolve)
    [ "$#" -eq 3 ] && [ "$2" = --answer ] || die 'usage: decisions.sh resolve <key> --answer <text>'
    KEY=$1; ANSWER=$3
    state_lock_acquire decisions
    open_json | jq -e --arg key "$KEY" '.[] | select(.key == $key)' >/dev/null || die "open decision not found: $KEY"
    jq -nc --arg key "$KEY" --arg answer "$ANSWER" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '{schema:"harness-decision.v1",action:"resolved",key:$key,answer:$answer,createdAt:$at}' >> "$FILE"
    state_lock_release; printf 'resolved: %s\n' "$KEY"
    ;;
  *) die 'usage: decisions.sh open|list|resolve ...' ;;
esac

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
# shellcheck source=scripts/harness-event-lib.sh
. "$HARNESS_ROOT/scripts/harness-event-lib.sh"

COMMAND=${1:-list}; shift || true
case "$COMMAND" in
  emit)
    [ "$#" -eq 4 ] || die 'usage: inbox.sh emit <task> <type> <generation> <message>'
    event_emit "$1" "$2" "$3" "$4"
    ;;
  list)
    [ "$#" -le 1 ] || die 'usage: inbox.sh list [--json]'
    JSON=$(event_unread_json)
    if [ "${1:-}" = --json ]; then printf '%s\n' "$JSON"; else printf '%s\n' "$JSON" | jq -r '.[] | "\(.id) · \(.task) · \(.type) · \(.message)"'; fi
    ;;
  acknowledge)
    [ "$#" -eq 1 ] || die 'usage: inbox.sh acknowledge <event-id>'
    ID=$1; EVENTS=$(event_file); ACKS=$(event_ack_file)
    if [ ! -f "$EVENTS" ] || ! jq -e --arg id "$ID" 'select(.id == $id)' "$EVENTS" >/dev/null; then die "event not found: $ID"; fi
    state_lock_acquire inbox; touch "$ACKS"
    if ! jq -e --arg id "$ID" 'select(.id == $id)' "$ACKS" >/dev/null 2>&1; then
      jq -nc --arg id "$ID" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '{schema:"harness-event-ack.v1",id:$id,acknowledgedAt:$at}' >> "$ACKS"
    fi
    state_lock_release; printf 'acknowledged: %s\n' "$ID"
    ;;
  drain)
    [ "$#" -eq 0 ] || die 'usage: inbox.sh drain'
    JSON=$(event_unread_json); printf '%s\n' "$JSON" | jq -r '.[] | "\(.id) · \(.task) · \(.type) · \(.message)"'
    printf '%s\n' "$JSON" | jq -r '.[].id' | while IFS= read -r ID; do "$0" acknowledge "$ID" >/dev/null; done
    ;;
  *) die 'usage: inbox.sh list [--json] | acknowledge <id> | drain' ;;
esac

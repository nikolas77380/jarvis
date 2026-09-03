#!/usr/bin/env bash
# Append-only event mechanics. Source after herdr-runtime-lib.sh and harness-state-lib.sh.

event_file() { printf '%s/events.jsonl\n' "$HARNESS_STATE"; }
event_ack_file() { printf '%s/event-acks.jsonl\n' "$HARNESS_STATE"; }

event_id() {
  printf '%s\0%s\0%s' "$1" "$2" "$3" | git hash-object --stdin | cut -c1-16 | sed 's/^/e_/'
}

event_emit() {
  # identity (5th, optional arg) is a JSON object carrying whatever immutable execution identity
  # (agent name, tab, session, generation, worktree head) the emitting caller can resolve at emit
  # time — resolved once here rather than re-derived later, so a consumer that requires an exact
  # identity match (agent-cleanup.sh) never has to guess it. Purely additive: existing 4-arg callers
  # get "{}", unchanged event_id/dedup semantics (still task+type+generation only).
  local task=$1 type=$2 generation=$3 message=$4 identity=${5:-'{}'} id file owned=false
  id=$(event_id "$task" "$type" "$generation")
  file=$(event_file)
  if [ "${STATE_LOCK_DIR:-}" != "$HARNESS_STATE/locks/inbox.lock" ]; then state_lock_acquire inbox; owned=true; fi
  mkdir -p "$HARNESS_STATE"
  touch "$file"
  if ! jq -e --arg id "$id" 'select(.id == $id)' "$file" >/dev/null 2>&1; then
    jq -nc --arg id "$id" --arg task "$task" --arg type "$type" --arg generation "$generation" \
      --arg message "$message" --argjson identity "$identity" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      '{schema:"harness-event.v1",id:$id,task:$task,type:$type,generation:$generation,message:$message,identity:$identity,createdAt:$at}' >> "$file"
  fi
  [ "$owned" = false ] || state_lock_release
  printf '%s\n' "$id"
}

event_unread_json() {
  local events acks
  events=$(event_file); acks=$(event_ack_file)
  mkdir -p "$HARNESS_STATE"; touch "$events" "$acks"
  jq -s --slurpfile acknowledgements "$acks" \
    'map(select(.id as $id | ([$acknowledgements[].id] | index($id) | not)))' "$events"
}

#!/usr/bin/env bash
# State and validation helpers for the opt-in Codex completion watcher.
# Source after herdr-runtime-lib.sh and harness-state-lib.sh.

CODEX_COMPLETION_SCHEMA=harness-codex-completion.v1

codex_completion_meta() {
  valid_task_id "$1" || die "invalid task id: $1"
  printf '%s/codex-completion/%s.meta\n' "$HARNESS_STATE" "$1"
}

codex_completion_require_token() {
  local value=$1 label=$2
  case "$value" in ''|*[!a-zA-Z0-9._:@/-]*) die "invalid $label: $value" ;; esac
}

codex_completion_clean_detail() {
  printf '%s' "$1" | tr '\r\n' '  ' | cut -c1-500
}

codex_completion_load() {
  local id=$1 file
  file=$(codex_completion_meta "$id")
  [ -f "$file" ] && [ ! -L "$file" ] || die "completion watcher state not found for $id"
  [ "$(meta_get "$file" schema)" = "$CODEX_COMPLETION_SCHEMA" ] \
    || die "completion watcher state has an unsupported or missing schema: $file"
  CC_FILE=$file
  CC_TASK=$(meta_get "$file" task)
  CC_STATUS=$(meta_get "$file" status)
  CC_ATTEMPT=$(meta_get "$file" attempt)
  CC_SOURCE_GENERATION=$(meta_get "$file" source_generation)
  CC_SOURCE_AGENT_NAME=$(meta_get "$file" source_agent_name)
  CC_SOURCE_ENGINE=$(meta_get "$file" source_engine)
  CC_SOURCE_ROLE=$(meta_get "$file" source_role)
  CC_SOURCE_META=$(meta_get "$file" source_meta)
  CC_SOURCE_CARD=$(meta_get "$file" source_card)
  CC_REPORT=$(meta_get "$file" report)
  CC_RECIPIENT_SESSION=$(meta_get "$file" recipient_session)
  CC_RECIPIENT_PANE=$(meta_get "$file" recipient_pane)
  CC_RECIPIENT_ID=$(meta_get "$file" recipient_agent_session)
  CC_WATCHER_PID=$(meta_get "$file" watcher_pid)
  CC_WATCHER_IDENTITY=$(meta_get "$file" watcher_identity)
  CC_CREATED_AT=$(meta_get "$file" created_at)
  CC_UPDATED_AT=$(meta_get "$file" updated_at)
  CC_DETAIL=$(meta_get "$file" detail)
}

codex_completion_write() {
  local detail state_dir
  require_fleet_mutation_allowed
  detail=$(codex_completion_clean_detail "${CC_DETAIL:-}")
  state_dir="$HARNESS_STATE/codex-completion"
  if [ -e "$state_dir" ]; then
    [ -d "$state_dir" ] && [ ! -L "$state_dir" ] || die "completion watcher state directory is malformed: $state_dir"
  else
    mkdir -p "$state_dir"
  fi
  CC_UPDATED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  atomic_meta_write "$CC_FILE" <<EOF
schema=$CODEX_COMPLETION_SCHEMA
task=$CC_TASK
status=$CC_STATUS
attempt=$CC_ATTEMPT
source_generation=$CC_SOURCE_GENERATION
source_agent_name=$CC_SOURCE_AGENT_NAME
source_engine=$CC_SOURCE_ENGINE
source_role=$CC_SOURCE_ROLE
source_meta=$CC_SOURCE_META
source_card=$CC_SOURCE_CARD
report=$CC_REPORT
recipient_session=$CC_RECIPIENT_SESSION
recipient_pane=$CC_RECIPIENT_PANE
recipient_agent_session=$CC_RECIPIENT_ID
watcher_pid=$CC_WATCHER_PID
watcher_identity=$CC_WATCHER_IDENTITY
created_at=$CC_CREATED_AT
updated_at=$CC_UPDATED_AT
detail=$detail
EOF
}

codex_completion_recipient_snapshot() {
  local session=$1 pane=$2 out
  out=$(herdr --session "$session" agent get "$pane" 2>/dev/null) || return 1
  printf '%s' "$out" | jq -e '.result.agent' >/dev/null 2>&1 || return 1
  printf '%s\n' "$out"
}

codex_completion_validate_recipient() {
  local snapshot=$1 expected_id=${2:-} engine pane identity status
  engine=$(printf '%s' "$snapshot" | jq -r '.result.agent.agent // empty')
  pane=$(printf '%s' "$snapshot" | jq -r '.result.agent.pane_id // empty')
  identity=$(printf '%s' "$snapshot" | jq -r '.result.agent.agent_session.value // empty')
  status=$(printf '%s' "$snapshot" | jq -r '.result.agent.agent_status // "unknown"')
  [ "$engine" = codex ] || { CODEX_COMPLETION_ERROR="recipient engine is $engine, expected codex"; return 1; }
  [ "$pane" = "$CC_RECIPIENT_PANE" ] || { CODEX_COMPLETION_ERROR="recipient pane changed from $CC_RECIPIENT_PANE to $pane"; return 1; }
  case "$identity" in
    ''|*[!a-zA-Z0-9._:@/-]*) CODEX_COMPLETION_ERROR="recipient agent session identity is missing or invalid"; return 1 ;;
  esac
  if [ -n "$expected_id" ] && [ "$identity" != "$expected_id" ]; then
    # shellcheck disable=SC2034 # consumed by the watcher after this sourced helper returns
    CODEX_COMPLETION_ERROR="recipient agent session changed"
    return 1
  fi
  case "$status" in working|idle|done|blocked) ;; *) status=unknown ;; esac
  # shellcheck disable=SC2034 # consumed by the watcher after this sourced helper returns
  CODEX_COMPLETION_RECIPIENT_ID=$identity
  # shellcheck disable=SC2034 # consumed by the watcher after this sourced helper returns
  CODEX_COMPLETION_RECIPIENT_STATUS=$status
}

codex_completion_status_json() {
  jq -nc \
    --arg task "$CC_TASK" \
    --arg status "$CC_STATUS" \
    --arg attempt "$CC_ATTEMPT" \
    --arg generation "$CC_SOURCE_GENERATION" \
    --arg sourceAgent "$CC_SOURCE_AGENT_NAME" \
    --arg sourceMeta "$CC_SOURCE_META" \
    --arg report "$CC_REPORT" \
    --arg session "$CC_RECIPIENT_SESSION" \
    --arg pane "$CC_RECIPIENT_PANE" \
    --arg recipientId "$CC_RECIPIENT_ID" \
    --arg detail "$CC_DETAIL" \
    --arg updatedAt "$CC_UPDATED_AT" \
    '{schema:"harness-codex-completion-status.v1",task:$task,status:$status,attempt:($attempt|tonumber),source:{generation:($generation|tonumber),agent:$sourceAgent,metadata:$sourceMeta,report:$report},recipient:{session:$session,pane:$pane,agentSession:$recipientId},detail:$detail,updatedAt:$updatedAt}'
}

codex_completion_process_is_live() {
  local observed
  [ -n "$CC_WATCHER_PID" ] && [ -n "$CC_WATCHER_IDENTITY" ] || return 1
  observed=$(state_process_identity "$CC_WATCHER_PID")
  [ -n "$observed" ] && [ "$observed" = "$CC_WATCHER_IDENTITY" ]
}

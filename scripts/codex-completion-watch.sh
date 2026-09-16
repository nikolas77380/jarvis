#!/usr/bin/env bash
# Register and run a plain-shell watcher that wakes an explicitly captured Codex lead.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
# shellcheck source=scripts/codex-completion-lib.sh
. "$HARNESS_ROOT/scripts/codex-completion-lib.sh"

usage() {
  die 'usage: codex-completion-watch.sh start <task-id> --session <name> --pane <pane-id> | status <task-id> | reconcile <task-id> [--retry|--delivered|--supersede]'
}

source_capture() {
  local id=$1 meta card generation role agent_name engine worktree
  meta=$(require_meta "$id")
  [ "$(meta_get "$meta" stopped)" != 1 ] || die "task $id is stopped"
  card=$(task_card "$id")
  generation=$(meta_get "$meta" generation); generation=${generation:-1}
  case "$generation" in ''|*[!0-9]*) die "task $id has invalid generation: $generation" ;; esac
  role=$(meta_get "$meta" agent); codex_completion_require_token "$role" 'source role'
  agent_name=$(meta_get "$meta" agent_name); codex_completion_require_token "$agent_name" 'source agent name'
  engine=$(meta_get "$meta" engine); case "$engine" in claude|codex) ;; *) die "task $id has invalid engine: $engine" ;; esac
  worktree=$(meta_get "$meta" worktree); [ -d "$worktree" ] || die "task $id worktree is unavailable: $worktree"
  SOURCE_META=$meta
  SOURCE_CARD=$card
  SOURCE_GENERATION=$generation
  SOURCE_ROLE=$role
  SOURCE_AGENT_NAME=$agent_name
  SOURCE_ENGINE=$engine
  SOURCE_REPORT="$worktree/reports/$id-$role.md"
}

quota_recovery_matches() {
  local id=$1 current_generation=$2 current_agent=$3 history line schema task from to old_agent new_agent note at
  local expected_generation=$CC_SOURCE_GENERATION expected_agent=$CC_SOURCE_AGENT_NAME matched=0
  history="$HARNESS_STATE/agent-history/$id.jsonl"
  [ -f "$history" ] && [ ! -L "$history" ] || return 1
  while IFS= read -r line; do
    schema=$(printf '%s' "$line" | jq -r '.schema // empty' 2>/dev/null) || return 1
    task=$(printf '%s' "$line" | jq -r '.task // empty' 2>/dev/null) || return 1
    at=$(printf '%s' "$line" | jq -r '.switchedAt // empty' 2>/dev/null) || return 1
    if [ "$schema" != harness-agent-switch.v1 ] || [ "$task" != "$id" ] || [ -z "$at" ]; then continue; fi
    if [ "$at" != "$CC_CREATED_AT" ] && [ "$at" \< "$CC_CREATED_AT" ]; then continue; fi
    from=$(printf '%s' "$line" | jq -r '.from // empty')
    to=$(printf '%s' "$line" | jq -r '.to // empty')
    old_agent=$(printf '%s' "$line" | jq -r '.oldAgent // empty')
    new_agent=$(printf '%s' "$line" | jq -r '.newAgent // empty')
    note=$(printf '%s' "$line" | jq -r '.note // empty')
    [ "$from" = "$CC_SOURCE_ENGINE" ] && [ "$to" = "$CC_SOURCE_ENGINE" ] \
      && [ "$old_agent" = "$expected_agent" ] && [ "${note#Provider quota reset.}" != "$note" ] || return 1
    expected_agent=$new_agent
    expected_generation=$((expected_generation + 1))
    matched=$((matched + 1))
  done < "$history"
  [ "$matched" -gt 0 ] && [ "$expected_generation" = "$current_generation" ] && [ "$expected_agent" = "$current_agent" ]
}

source_still_matches() {
  local id=$1 meta card generation agent_name role
  CODEX_COMPLETION_SOURCE_REFRESH_GENERATION=''
  CODEX_COMPLETION_SOURCE_REFRESH_AGENT=''
  meta=$(task_meta "$id")
  [ -f "$meta" ] && [ ! -L "$meta" ] || { CODEX_COMPLETION_ERROR="source task metadata disappeared"; return 1; }
  [ "$(meta_get "$meta" schema)" = harness-herdr-task.v1 ] || { CODEX_COMPLETION_ERROR="source task metadata schema changed"; return 1; }
  [ "$(meta_get "$meta" stopped)" != 1 ] || { CODEX_COMPLETION_ERROR="source task was stopped"; return 1; }
  generation=$(meta_get "$meta" generation); generation=${generation:-1}
  agent_name=$(meta_get "$meta" agent_name)
  [ "$(meta_get "$meta" engine)" = "$CC_SOURCE_ENGINE" ] || { CODEX_COMPLETION_ERROR="source task engine changed"; return 1; }
  role=$(meta_get "$meta" agent)
  [ "$role" = "$CC_SOURCE_ROLE" ] || { CODEX_COMPLETION_ERROR="source task role changed"; return 1; }
  if ! card=$(task_card "$id" 2>/dev/null); then CODEX_COMPLETION_ERROR="source task card is missing or ambiguous"; return 1; fi
  [ "$card" = "$CC_SOURCE_CARD" ] || { CODEX_COMPLETION_ERROR="source task card changed"; return 1; }
  if [ "$generation" = "$CC_SOURCE_GENERATION" ] && [ "$agent_name" = "$CC_SOURCE_AGENT_NAME" ]; then return 0; fi
  if quota_recovery_matches "$id" "$generation" "$agent_name"; then
    CODEX_COMPLETION_SOURCE_REFRESH_GENERATION=$generation
    CODEX_COMPLETION_SOURCE_REFRESH_AGENT=$agent_name
    return 0
  fi
  CODEX_COMPLETION_ERROR="source task generation or agent changed without a recorded quota recovery"
  return 1
}

refresh_source_if_needed() {
  local id=$1
  if ! source_still_matches "$id"; then return 1; fi
  [ -n "$CODEX_COMPLETION_SOURCE_REFRESH_GENERATION" ] || return 0
  state_lock_acquire "$id"
  codex_completion_load "$id"
  if ! source_still_matches "$id"; then state_lock_release; return 1; fi
  CC_SOURCE_GENERATION=$CODEX_COMPLETION_SOURCE_REFRESH_GENERATION
  CC_SOURCE_AGENT_NAME=$CODEX_COMPLETION_SOURCE_REFRESH_AGENT
  CC_STATUS=pending
  CC_DETAIL='source binding advanced through recorded quota recovery'
  CC_WATCHER_PID=$$
  CC_WATCHER_IDENTITY=$(state_process_identity "$$")
  codex_completion_write
  state_lock_release
}

transition() {
  local id=$1 status=$2 detail=$3
  state_lock_acquire "$id"
  codex_completion_load "$id"
  if [ "$CC_STATUS" = delivered ] && [ "$status" != delivered ]; then
    state_lock_release
    die "completion watcher is already delivered for $id"
  fi
  CC_STATUS=$status
  CC_DETAIL=$detail
  CC_WATCHER_PID=$$
  CC_WATCHER_IDENTITY=$(state_process_identity "$$")
  codex_completion_write
  state_lock_release
}

fail_claim() {
  local id=$1 detail=$2
  transition "$id" failed "$detail"
  printf 'error: %s\n' "$detail" >&2
  return 1
}

registration_preflight() {
  local id=$1 existing=$2
  REGISTRATION_REPLACES_DELIVERED=0
  source_capture "$id"
  [ -e "$existing" ] || return 0
  if [ ! -f "$existing" ] || [ -L "$existing" ]; then
    CODEX_COMPLETION_ERROR="completion watcher state is malformed: $existing"
    return 1
  fi
  codex_completion_load "$id"
  if [ "$CC_TASK" != "$id" ]; then
    CODEX_COMPLETION_ERROR="completion watcher state names a different task: $CC_TASK"
    return 1
  fi
  if [ "$CC_STATUS" != delivered ]; then
    CODEX_COMPLETION_ERROR="completion watcher already registered for $id in state $CC_STATUS; use status or reconcile"
    return 1
  fi
  case "$CC_SOURCE_GENERATION" in
    ''|*[!0-9]*) CODEX_COMPLETION_ERROR="completion watcher has invalid source generation: $CC_SOURCE_GENERATION"; return 1 ;;
  esac
  if [ "$SOURCE_GENERATION" -le "$CC_SOURCE_GENERATION" ]; then
    CODEX_COMPLETION_ERROR="completion watcher already delivered generation $CC_SOURCE_GENERATION for $id; canonical generation $SOURCE_GENERATION is not newer"
    return 1
  fi
  REGISTRATION_REPLACES_DELIVERED=1
}

archive_delivered_claim() {
  local id=$1 archive_dir archive_path stamp
  archive_dir="$HARNESS_STATE/codex-completion/archive"
  if [ -e "$archive_dir" ]; then
    [ -d "$archive_dir" ] && [ ! -L "$archive_dir" ] \
      || die "completion watcher archive is malformed: $archive_dir"
  else
    mkdir -p "$archive_dir"
  fi
  stamp=$(date -u '+%Y%m%dT%H%M%SZ')
  archive_path="$archive_dir/$id.g$CC_SOURCE_GENERATION.a$CC_ATTEMPT.$stamp.meta"
  [ ! -e "$archive_path" ] || die "completion watcher archive already exists: $archive_path"
  mv "$CC_FILE" "$archive_path"
}

register_claim() {
  local id=$1 session=$2 pane=$3 snapshot identity existing error
  require_fleet_mutation_allowed
  codex_completion_require_token "$session" 'recipient session'
  codex_completion_require_token "$pane" 'recipient pane'

  state_lock_acquire "$id"
  existing=$(codex_completion_meta "$id")
  if ! registration_preflight "$id" "$existing"; then
    error=$CODEX_COMPLETION_ERROR
    state_lock_release
    die "$error"
  fi
  state_lock_release

  CC_RECIPIENT_PANE=$pane
  if ! snapshot=$(codex_completion_recipient_snapshot "$session" "$pane"); then
    die "recipient is unavailable in Herdr session $session at pane $pane"
  fi
  if ! codex_completion_validate_recipient "$snapshot" ''; then die "$CODEX_COMPLETION_ERROR"; fi
  identity=$CODEX_COMPLETION_RECIPIENT_ID

  state_lock_acquire "$id"
  if ! registration_preflight "$id" "$existing"; then
    error=$CODEX_COMPLETION_ERROR
    state_lock_release
    die "$error"
  fi
  if [ "$REGISTRATION_REPLACES_DELIVERED" = 1 ]; then archive_delivered_claim "$id"; fi
  CC_FILE=$existing
  CC_TASK=$id
  CC_STATUS=pending
  CC_ATTEMPT=1
  CC_SOURCE_GENERATION=$SOURCE_GENERATION
  CC_SOURCE_AGENT_NAME=$SOURCE_AGENT_NAME
  CC_SOURCE_ENGINE=$SOURCE_ENGINE
  CC_SOURCE_ROLE=$SOURCE_ROLE
  CC_SOURCE_META=$SOURCE_META
  CC_SOURCE_CARD=$SOURCE_CARD
  CC_REPORT=$SOURCE_REPORT
  CC_RECIPIENT_SESSION=$session
  CC_RECIPIENT_PANE=$pane
  CC_RECIPIENT_ID=$identity
  CC_WATCHER_PID=$$
  CC_WATCHER_IDENTITY=$(state_process_identity "$$")
  CC_CREATED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  CC_DETAIL='registered; waiting for source task'
  codex_completion_write
  state_lock_release
}

run_claim() {
  local id=$1 snapshot status prompt
  codex_completion_load "$id"
  case "$CC_STATUS" in pending|waiting|failed|uncertain) ;; delivered) return 0 ;; delivering) die "delivery is already in progress or ambiguous for $id; reconcile it first" ;; *) die "invalid completion watcher state for $id: $CC_STATUS" ;; esac

  if ! "$HARNESS_ROOT/scripts/agent-wait.sh" "$id" >/dev/null; then
    fail_claim "$id" 'source task wait failed'
    return 1
  fi
  codex_completion_load "$id"
  if ! refresh_source_if_needed "$id"; then fail_claim "$id" "$CODEX_COMPLETION_ERROR"; return 1; fi

  if ! snapshot=$(codex_completion_recipient_snapshot "$CC_RECIPIENT_SESSION" "$CC_RECIPIENT_PANE"); then
    fail_claim "$id" 'recipient lookup failed after source task settled'
    return 1
  fi
  if ! codex_completion_validate_recipient "$snapshot" "$CC_RECIPIENT_ID"; then fail_claim "$id" "$CODEX_COMPLETION_ERROR"; return 1; fi
  status=$CODEX_COMPLETION_RECIPIENT_STATUS
  if [ "$status" = blocked ]; then
    transition "$id" waiting 'recipient is blocked; resolve it and run reconcile --retry'
    return 0
  fi
  if [ "$status" = working ]; then
    transition "$id" waiting 'recipient is working; waiting outside the model'
    if ! herdr --session "$CC_RECIPIENT_SESSION" agent wait "$CC_RECIPIENT_PANE" >/dev/null; then
      fail_claim "$id" 'recipient wait failed'
      return 1
    fi
    codex_completion_load "$id"
    if ! snapshot=$(codex_completion_recipient_snapshot "$CC_RECIPIENT_SESSION" "$CC_RECIPIENT_PANE"); then
      fail_claim "$id" 'recipient lookup failed after recipient wait'
      return 1
    fi
    if ! codex_completion_validate_recipient "$snapshot" "$CC_RECIPIENT_ID"; then fail_claim "$id" "$CODEX_COMPLETION_ERROR"; return 1; fi
    status=$CODEX_COMPLETION_RECIPIENT_STATUS
    if [ "$status" = blocked ]; then
      transition "$id" waiting 'recipient became blocked; resolve it and run reconcile --retry'
      return 0
    fi
  fi
  case "$status" in idle|done) ;; *) fail_claim "$id" "recipient did not settle safely: $status"; return 1 ;; esac

  codex_completion_load "$id"
  if ! refresh_source_if_needed "$id"; then fail_claim "$id" "$CODEX_COMPLETION_ERROR"; return 1; fi
  if ! snapshot=$(codex_completion_recipient_snapshot "$CC_RECIPIENT_SESSION" "$CC_RECIPIENT_PANE"); then
    fail_claim "$id" 'final recipient lookup failed'
    return 1
  fi
  if ! codex_completion_validate_recipient "$snapshot" "$CC_RECIPIENT_ID"; then fail_claim "$id" "$CODEX_COMPLETION_ERROR"; return 1; fi
  case "$CODEX_COMPLETION_RECIPIENT_STATUS" in idle|done) ;; blocked) transition "$id" waiting 'recipient became blocked before delivery'; return 0 ;; *) fail_claim "$id" 'recipient became busy before delivery'; return 1 ;; esac

  transition "$id" delivering 'prompt command started; a crash from this state is ambiguous'
  codex_completion_load "$id"
  prompt="Task $id has settled. Inspect canonical task metadata at $CC_SOURCE_META and the task report at $CC_REPORT, then checkpoint the card and continue the existing review and validation workflow."
  if herdr --session "$CC_RECIPIENT_SESSION" agent prompt "$CC_RECIPIENT_PANE" "$prompt" >/dev/null; then
    transition "$id" delivered 'completion prompt accepted by Herdr'
    return 0
  fi
  transition "$id" uncertain 'Herdr prompt returned failure after delivery began; do not retry automatically'
  printf 'error: completion delivery is uncertain for %s; inspect status and reconcile explicitly\n' "$id" >&2
  return 1
}

status_command() {
  local id=$1
  command -v jq >/dev/null 2>&1 || die 'jq is required'
  codex_completion_load "$id"
  codex_completion_status_json
}

reconcile_command() {
  local id=$1 action=${2:-} archive_dir archive_path stamp
  require_fleet_mutation_allowed
  case "$action" in ''|--retry|--delivered|--supersede) ;; *) usage ;; esac
  state_lock_acquire "$id"
  codex_completion_load "$id"
  if codex_completion_process_is_live && [ "$CC_WATCHER_PID" != "$$" ]; then
    state_lock_release
    die "completion watcher is still active for $id (pid $CC_WATCHER_PID)"
  fi
  if [ "$CC_STATUS" = delivering ]; then
    CC_STATUS=uncertain
    CC_DETAIL='delivery process ended while prompt outcome was ambiguous; no automatic resend'
    CC_WATCHER_PID=$$
    CC_WATCHER_IDENTITY=$(state_process_identity "$$")
    codex_completion_write
  fi
  case "$action" in
    '') state_lock_release; status_command "$id" ;;
    --delivered)
      [ "$CC_STATUS" = uncertain ] || { state_lock_release; die "--delivered requires uncertain state, observed: $CC_STATUS"; }
      CC_STATUS=delivered
      CC_DETAIL='operator reconciled ambiguous attempt as delivered'
      codex_completion_write
      state_lock_release
      status_command "$id"
      ;;
    --retry)
      case "$CC_STATUS" in pending|waiting|failed|uncertain) ;; *) state_lock_release; die "--retry is not valid from state: $CC_STATUS" ;; esac
      CC_ATTEMPT=$((CC_ATTEMPT + 1))
      CC_STATUS=pending
      CC_DETAIL='operator explicitly requested retry'
      CC_WATCHER_PID=$$
      CC_WATCHER_IDENTITY=$(state_process_identity "$$")
      codex_completion_write
      state_lock_release
      run_claim "$id"
      ;;
    --supersede)
      case "$CC_STATUS" in delivered) state_lock_release; die 'a delivered watcher cannot be superseded' ;; esac
      archive_dir="$HARNESS_STATE/codex-completion/archive"
      if [ -e "$archive_dir" ]; then
        [ -d "$archive_dir" ] && [ ! -L "$archive_dir" ] || { state_lock_release; die "completion watcher archive is malformed: $archive_dir"; }
      else
        mkdir -p "$archive_dir"
      fi
      stamp=$(date -u '+%Y%m%dT%H%M%SZ')
      archive_path="$archive_dir/$id.g$CC_SOURCE_GENERATION.a$CC_ATTEMPT.$stamp.meta"
      [ ! -e "$archive_path" ] || { state_lock_release; die "completion watcher archive already exists: $archive_path"; }
      CC_STATUS=failed
      CC_DETAIL='operator superseded this claim; a new explicit start is required'
      codex_completion_write
      mv "$CC_FILE" "$archive_path"
      state_lock_release
      jq -nc --arg task "$id" --arg archive "$archive_path" \
        '{schema:"harness-codex-completion-reconcile.v1",task:$task,status:"superseded",archive:$archive}'
      ;;
  esac
}

COMMAND=${1:-}
ID=${2:-}
[ -n "$COMMAND" ] && [ -n "$ID" ] || usage
valid_task_id "$ID" || die "invalid task id: $ID"
require_tools

case "$COMMAND" in
  start)
    [ "$#" -eq 6 ] && [ "$3" = --session ] && [ "$5" = --pane ] || usage
    register_claim "$ID" "$4" "$6"
    run_claim "$ID"
    ;;
  status)
    [ "$#" -eq 2 ] || usage
    status_command "$ID"
    ;;
  reconcile)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
    reconcile_command "$ID" "${3:-}"
    ;;
  *) usage ;;
esac

#!/usr/bin/env bash
# Harness-native, resumable validation pipeline for an existing task worktree.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  clean-slate-protocol.sh run <task-id>
  clean-slate-protocol.sh status <task-id> [--json]
  clean-slate-protocol.sh respond <task-id> --action fix|approve|skip
  clean-slate-protocol.sh abort <task-id>
  clean-slate-protocol.sh logs <task-id>
EOF
  exit 2
}

clean_dir() { printf '%s/clean-slate\n' "$HARNESS_STATE"; }
clean_meta() { valid_task_id "$1" || die "invalid task id: $1"; printf '%s/%s.meta\n' "$(clean_dir)" "$1"; }

clean_require_meta() {
  local file
  file=$(clean_meta "$1")
  [ -f "$file" ] && [ ! -L "$file" ] || die "clean-slate run not found for $1"
  [ "$(meta_get "$file" schema)" = harness-clean-slate.v1 ] || die "unsupported clean-slate state: $file"
  printf '%s\n' "$file"
}

clean_write() {
  local destination=$1 tmp
  mkdir -p "$(clean_dir)"
  tmp=$(mktemp "$(clean_dir)/.run.XXXXXX")
  cat > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$destination"
}

clean_set() {
  local file=$1 key=$2 value=$3 tmp
  tmp=$(mktemp "$(clean_dir)/.update.XXXXXX")
  awk -F= -v key="$key" -v value="$value" '
    $1 == key { print key "=" value; found=1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

clean_log() {
  local file=$1 message=$2 log
  log=$(meta_get "$file" log)
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$message" >> "$log"
}

clean_summary() {
  local file=$1 task mode state round
  task=$(meta_get "$file" task)
  mode=$(meta_get "$file" mode)
  state=$(meta_get "$file" state)
  round=$(meta_get "$file" round)
  printf 'clean-slate: %s · mode=%s · state=%s · round=%s\n' "$task" "$mode" "$state" "$round"
}

command_run() {
  local id=$1 card task_state project worktree mode config head run_dir log state file
  file=$(clean_meta "$id")
  [ ! -e "$file" ] || die "clean-slate run already exists for $id; use status or abort"
  card=$(task_card "$id")
  task_state=$(require_meta "$id")
  project=$(meta_get "$task_state" project)
  worktree=$(meta_get "$task_state" worktree)
  [ -d "$worktree" ] || die "task worktree is unavailable: $worktree"
  mode=$(card_field "$card" Validation)
  mode=${mode:-strict}
  case "$mode" in strict|direct) ;; *) die "Validation must be strict or direct, got: $mode" ;; esac
  config="$HARNESS_ROOT/config/projects/$project.json"
  [ -f "$config" ] || die "project validation config not found: $config"
  jq -e '.baseBranch | type == "string"' "$config" >/dev/null || die "invalid project config: baseBranch is required"
  jq -e '(.checks // []) | type == "array" and all(.[]; type == "array" and length > 0 and all(.[]; type == "string"))' "$config" >/dev/null \
    || die "invalid project config: checks must be arrays of argument strings"
  head=$(git -C "$worktree" rev-parse HEAD)
  run_dir="$worktree/.clean-slate/$id"
  mkdir -p "$run_dir"
  log="$run_dir/events.log"
  : > "$log"
  state=reviewing
  [ "$mode" = strict ] || state=verifying
  clean_write "$file" <<EOF
schema=harness-clean-slate.v1
task=$id
project=$project
mode=$mode
state=$state
round=1
head=$head
reviewed_head=
worktree=$worktree
config=$config
run_dir=$run_dir
log=$log
stage_agent=
started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
updated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF
  clean_log "$file" "run started mode=$mode head=$head"
  clean_log "$file" "entered state=$state"
  printf 'started: %s · mode=%s · state=%s\n' "$id" "$mode" "$state"
}

command_status() {
  local id=$1 format=${2:-} file
  file=$(clean_require_meta "$id")
  if [ "$format" = --json ]; then
    jq -n \
      --arg schema "$(meta_get "$file" schema)" \
      --arg task "$(meta_get "$file" task)" \
      --arg project "$(meta_get "$file" project)" \
      --arg mode "$(meta_get "$file" mode)" \
      --arg state "$(meta_get "$file" state)" \
      --argjson round "$(meta_get "$file" round)" \
      --arg head "$(meta_get "$file" head)" \
      '{schema:$schema,task:$task,project:$project,mode:$mode,state:$state,round:$round,head:$head}'
  else
    [ -z "$format" ] || usage
    clean_summary "$file"
  fi
}

command_respond() {
  local id=$1 action=$2 file state next
  file=$(clean_require_meta "$id")
  state=$(meta_get "$file" state)
  case "$state" in reviewing|awaiting-response) ;; *) die "cannot respond while state=$state" ;; esac
  case "$action" in
    fix) next=fixing ;;
    approve|skip) next=verifying ;;
    *) usage ;;
  esac
  clean_set "$file" state "$next"
  clean_set "$file" updated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  clean_log "$file" "response action=$action state=$next"
  printf 'updated: %s · action=%s · state=%s\n' "$id" "$action" "$next"
}

command_abort() {
  local id=$1 file state
  file=$(clean_require_meta "$id")
  state=$(meta_get "$file" state)
  case "$state" in ready|failed|aborted) die "cannot abort terminal state=$state" ;; esac
  clean_set "$file" state aborted
  clean_set "$file" updated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  clean_log "$file" "run aborted"
  printf 'aborted: %s · state=aborted\n' "$id"
}

command_logs() {
  local file log
  file=$(clean_require_meta "$1")
  log=$(meta_get "$file" log)
  [ -f "$log" ] || die "run log is unavailable: $log"
  cat "$log"
}

[ "$#" -ge 2 ] || usage
COMMAND=$1
ID=$2
shift 2
valid_task_id "$ID" || die "invalid task id: $ID"
case "$COMMAND" in
  run) [ "$#" -eq 0 ] || usage; command_run "$ID" ;;
  status) [ "$#" -le 1 ] || usage; command_status "$ID" "${1:-}" ;;
  respond)
    [ "$#" -eq 2 ] && [ "$1" = --action ] || usage
    command_respond "$ID" "$2"
    ;;
  abort) [ "$#" -eq 0 ] || usage; command_abort "$ID" ;;
  logs) [ "$#" -eq 0 ] || usage; command_logs "$ID" ;;
  *) usage ;;
esac

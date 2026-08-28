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

clean_exclude_artifacts() {
  local worktree=$1 exclude
  exclude=$(git -C "$worktree" rev-parse --git-path info/exclude)
  case "$exclude" in /*) ;; *) exclude="$worktree/$exclude" ;; esac
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  grep -qxF '.clean-slate/' "$exclude" || printf '.clean-slate/\n' >> "$exclude"
}

clean_stage_prompt() {
  local file=$1 stage=$2 round worktree run_dir prompt result config base reviewed range
  round=$(meta_get "$file" round)
  worktree=$(meta_get "$file" worktree)
  run_dir=$(meta_get "$file" run_dir)
  prompt="$run_dir/$stage-$round.prompt.md"
  result="$run_dir/$stage-$round.json"
  config=$(meta_get "$file" config)
  case "$stage" in
    review)
      base=$(jq -r '.baseBranch' "$config")
      reviewed=$(meta_get "$file" reviewed_head)
      if [ -n "$reviewed" ]; then range="$reviewed..HEAD"; else range="$base...HEAD"; fi
      cat > "$prompt" <<EOF
# Clean Slate review — round $round

Review the task branch in $worktree. Inspect the range: git diff $range. Follow project instructions.
Classify every finding as actionable or needs-decision. Also decide whether docs or
additional targeted checks are needed. Do not edit application files.

Write exactly one valid JSON object to $result:

{"outcome":"approved|findings","summary":"...","findings":[{"id":"R1","class":"actionable|needs-decision","message":"..."}]}
EOF
      ;;
    fix)
      cat > "$prompt" <<EOF
# Clean Slate fixes — round $round

Read $run_dir/review-$round.json. Fix only findings classified actionable; do not guess through
needs-decision findings. Run the narrow checks justified by the changes and commit the fixes. Write
exactly one valid JSON object to $result:

{"outcome":"fixed|needs-decision|failed","newHead":"<git HEAD>","summary":"..."}
EOF
      ;;
    *) die "unknown clean-slate stage: $stage" ;;
  esac
  printf '%s\n' "$prompt"
}

clean_launch_stage() {
  local file=$1 stage=$2 prompt task round role role_file worktree workspace out tab pane name system key existing model effort
  local -a claude_args
  prompt=$(clean_stage_prompt "$file" "$stage")
  task=$(meta_get "$file" task)
  round=$(meta_get "$file" round)
  key="${stage}_agent"
  if [ "${HARNESS_CLEAN_SLATE_NO_LAUNCH:-0}" = 1 ]; then
    clean_set "$file" stage_agent disabled
    clean_log "$file" "prepared stage=$stage round=$round launch=disabled"
    return
  fi
  require_tools
  case "$stage" in review) role=clean-slate-reviewer ;; fix) role=clean-slate-fixer ;; esac
  role_file="$HARNESS_ROOT/agents/$role.md"
  [ -f "$role_file" ] || die "clean-slate role not found: $role_file"
  existing=$(meta_get "$file" "$key")
  if [ -n "$existing" ] && [ "$(agent_status "$existing")" != unknown ]; then
    herdr_call agent prompt "$existing" "$(cat "$prompt")" >/dev/null
    clean_set "$file" stage_agent "$existing"
    clean_log "$file" "resumed stage=$stage round=$round agent=$existing"
    return
  fi
  worktree=$(meta_get "$file" worktree)
  workspace=$(workspace_ensure)
  out=$(herdr_call tab create --workspace "$workspace" --cwd "$worktree" --label "clean-$task-$stage" --no-focus)
  tab=$(printf '%s' "$out" | jq -er '.result.tab.tab_id')
  pane=$(printf '%s' "$out" | jq -er '.result.root_pane.pane_id')
  name=$(agent_runtime_name "clean-$task-$stage")
  system="$(meta_get "$file" run_dir)/$stage.system.md"
  { cat "$HARNESS_ROOT/RULES.md"; printf '\n\n'; cat "$role_file"; } > "$system"
  model=$(role_field "$role_file" model)
  effort=$(role_field "$role_file" effort)
  claude_args=(--append-system-prompt-file "$system" --name "clean-$task-$stage" --permission-mode auto)
  [ -z "$model" ] || claude_args+=(--model "$model")
  [ -z "$effort" ] || claude_args+=(--effort "$effort")
  herdr_call agent start "$name" --kind claude --pane "$pane" -- \
    "${claude_args[@]}" >/dev/null
  herdr_call agent prompt "$name" "$(cat "$prompt")" >/dev/null
  clean_set "$file" "$key" "$name"
  clean_set "$file" "${stage}_tab" "$tab"
  clean_set "$file" stage_agent "$name"
  clean_log "$file" "launched stage=$stage round=$round agent=$name pane=$pane"
}

clean_publish() {
  local file=$1 config worktree publish branch base card title body output pr
  config=$(meta_get "$file" config)
  publish=$(jq -r 'if has("publish") then .publish else true end' "$config")
  if [ "$publish" = false ]; then
    clean_set "$file" state ready
    clean_log "$file" "publishing disabled; entered state=ready"
    return
  fi
  command -v gh-axi >/dev/null 2>&1 || { clean_set "$file" state failed; die "gh-axi is required to publish"; }
  worktree=$(meta_get "$file" worktree)
  branch=$(git -C "$worktree" branch --show-current)
  base=$(jq -r '.baseBranch' "$config")
  card=$(task_card "$(meta_get "$file" task)")
  title=$(sed -n 's/^#[[:space:]]*//p' "$card" | head -1)
  [ -n "$title" ] || title="$(meta_get "$file" task)"
  body="$(meta_get "$file" run_dir)/pull-request.md"
  {
    printf 'Validated by Clean Slate Protocol.\n\n'
    printf -- '- Mode: %s\n' "$(meta_get "$file" mode)"
    printf -- '- Review rounds: %s\n' "$(meta_get "$file" round)"
    printf -- '- Validated HEAD: %s\n' "$(git -C "$worktree" rev-parse HEAD)"
  } > "$body"
  clean_set "$file" state publishing
  clean_log "$file" "entered state=publishing"
  if ! git -C "$worktree" push -u origin "$branch"; then
    clean_set "$file" state failed
    clean_log "$file" "publishing failed during git push"
    return 1
  fi
  if ! output=$(cd "$worktree" && gh-axi pr create --title "$title" --body-file "$body" --base "$base" --head "$branch"); then
    clean_set "$file" state failed
    clean_log "$file" "publishing failed during PR creation"
    return 1
  fi
  printf '%s\n' "$output" > "$(meta_get "$file" run_dir)/pr-create.log"
  pr=$(printf '%s\n' "$output" | sed -n -E 's/.*number:[[:space:]]*([0-9]+).*/\1/p' | head -1)
  [ -n "$pr" ] || { clean_set "$file" state failed; die "could not parse PR number from gh-axi output"; }
  clean_set "$file" pr "$pr"
  clean_set "$file" state ci
  clean_log "$file" "created pr=$pr; entered state=ci"
}

clean_verify() {
  local file=$1 config worktree run_dir index row log failed
  config=$(meta_get "$file" config)
  worktree=$(meta_get "$file" worktree)
  run_dir=$(meta_get "$file" run_dir)
  clean_set "$file" state verifying
  clean_log "$file" "entered state=verifying"
  index=0
  failed=0
  while IFS= read -r row; do
    index=$((index + 1))
    IFS=$'\t' read -r -a check_args <<< "$row"
    log="$run_dir/check-$index.log"
    printf 'command:' > "$log"
    printf ' %q' "${check_args[@]}" >> "$log"
    printf '\n' >> "$log"
    if (cd "$worktree" && "${check_args[@]}") >> "$log" 2>&1; then
      clean_log "$file" "check=$index outcome=pass"
    else
      failed=1
      clean_log "$file" "check=$index outcome=fail log=$log"
      break
    fi
  done < <(jq -r '.checks[]? | @tsv' "$config")
  if [ "$failed" = 1 ]; then
    clean_set "$file" state failed
    return 1
  fi
  clean_publish "$file"
}

clean_reconcile_ci() {
  local file=$1 state pr worktree output
  state=$(meta_get "$file" state)
  [ "$state" = ci ] || return 0
  pr=$(meta_get "$file" pr)
  worktree=$(meta_get "$file" worktree)
  output=$(cd "$worktree" && gh-axi pr checks "$pr") || { clean_set "$file" state failed; return 0; }
  printf '%s\n' "$output" > "$(meta_get "$file" run_dir)/ci.log"
  if printf '%s\n' "$output" | grep -Eq '[1-9][0-9]* failed'; then
    clean_set "$file" state failed
    clean_log "$file" "ci outcome=fail"
  elif printf '%s\n' "$output" | grep -Eq '[1-9][0-9]* pending'; then
    clean_log "$file" "ci outcome=pending"
  else
    clean_set "$file" state ready
    clean_log "$file" "ci outcome=pass; entered state=ready"
  fi
}

clean_reconcile() {
  local file=$1 state round run_dir result outcome worktree new_head current_head
  state=$(meta_get "$file" state)
  round=$(meta_get "$file" round)
  run_dir=$(meta_get "$file" run_dir)
  case "$state" in
    reviewing)
      result="$run_dir/review-$round.json"
      [ -f "$result" ] || return 0
      jq -e '.outcome == "approved" or .outcome == "findings"' "$result" >/dev/null \
        || die "invalid reviewer result: $result"
      outcome=$(jq -r '.outcome' "$result")
      current_head=$(git -C "$(meta_get "$file" worktree)" rev-parse HEAD)
      clean_set "$file" reviewed_head "$current_head"
      if [ "$outcome" = approved ]; then clean_set "$file" state verifying; else clean_set "$file" state awaiting-response; fi
      clean_log "$file" "completed stage=review round=$round outcome=$outcome"
      [ "$outcome" != approved ] || clean_verify "$file" || true
      ;;
    fixing)
      result="$run_dir/fix-$round.json"
      [ -f "$result" ] || return 0
      jq -e '.outcome == "fixed" or .outcome == "needs-decision" or .outcome == "failed"' "$result" >/dev/null \
        || die "invalid fixer result: $result"
      outcome=$(jq -r '.outcome' "$result")
      if [ "$outcome" != fixed ]; then
        clean_set "$file" state awaiting-response
        clean_log "$file" "completed stage=fix round=$round outcome=$outcome"
        return
      fi
      new_head=$(jq -er '.newHead' "$result") || die "fixer result has no newHead: $result"
      worktree=$(meta_get "$file" worktree)
      current_head=$(git -C "$worktree" rev-parse HEAD)
      [ "$new_head" = "$current_head" ] || die "fixer result HEAD does not match worktree HEAD"
      clean_set "$file" head "$new_head"
      if [ "$round" -ge 2 ]; then
        clean_set "$file" state awaiting-response
        clean_log "$file" "review ceiling reached after round=$round"
      else
        round=$((round + 1))
        clean_set "$file" round "$round"
        clean_set "$file" state reviewing
        clean_log "$file" "completed stage=fix; entered state=reviewing round=$round"
        clean_launch_stage "$file" review
      fi
      ;;
  esac
  clean_reconcile_ci "$file"
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
  [ -z "$(git -C "$worktree" status --porcelain)" ] \
    || die "task worktree must be clean and committed before validation: $worktree"
  mode=$(card_field "$card" Validation)
  mode=${mode:-strict}
  case "$mode" in strict|direct) ;; *) die "Validation must be strict or direct, got: $mode" ;; esac
  config="$HARNESS_ROOT/config/projects/$project.json"
  [ -f "$config" ] || die "project validation config not found: $config"
  jq -e '.baseBranch | type == "string"' "$config" >/dev/null || die "invalid project config: baseBranch is required"
  jq -e '(.checks // []) | type == "array" and all(.[]; type == "array" and length > 0 and all(.[]; type == "string"))' "$config" >/dev/null \
    || die "invalid project config: checks must be arrays of argument strings"
  jq -e '(.publish == null) or (.publish | type == "boolean")' "$config" >/dev/null \
    || die "invalid project config: publish must be boolean"
  head=$(git -C "$worktree" rev-parse HEAD)
  run_dir="$worktree/.clean-slate/$id"
  clean_exclude_artifacts "$worktree"
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
  if [ "$mode" = strict ]; then clean_launch_stage "$file" review; else clean_verify "$file" || true; fi
  printf 'started: %s · mode=%s · state=%s\n' "$id" "$mode" "$(meta_get "$file" state)"
}

command_status() {
  local id=$1 format=${2:-} file
  file=$(clean_require_meta "$id")
  clean_reconcile "$file"
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
  if [ "$action" = fix ]; then clean_launch_stage "$file" fix; else clean_verify "$file" || true; fi
  printf 'updated: %s · action=%s · state=%s\n' "$id" "$action" "$(meta_get "$file" state)"
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

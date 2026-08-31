#!/usr/bin/env bash
# Hand a task from its engineer to a reviewer, in the same worktree and branch, same engine.
#
# Why this exists: agent-spawn.sh always creates a fresh worktree+branch named after the task id,
# so it cannot be used a second time for the same id once an engineer has already spawned into it —
# it fails outright ("worktree path already exists"). agent-switch.sh reuses the worktree but only
# ever swaps the RUNTIME ENGINE (claude<->codex), never the role — it reads `agent` straight out of
# the existing metadata and keeps it unchanged. Neither script can move a task from its engineer to
# an independent reviewer, which every task in this pipeline needs before it can be approved. This
# is that missing step, built the same way agent-switch.sh is: reuse the worktree, bump the
# generation, verify nothing changed underneath between the old agent settling and the new one
# starting, and only close the old tab after the new one is confirmed prompted.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
# shellcheck source=scripts/agent-engine-lib.sh
. "$HARNESS_ROOT/scripts/agent-engine-lib.sh"

ID=${1:-}; ROLE_NAME=${2:-}
if [ "$#" -lt 2 ]; then die 'usage: agent-review.sh <task-id> <reviewer-role> --brief-file <path> [--engine claude|codex]'; fi
shift 2
BRIEF_FILE=''; EXPLICIT_ENGINE=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --brief-file) BRIEF_FILE=$2; shift 2 ;;
    --engine) EXPLICIT_ENGINE=$2; shift 2 ;;
    *) die "usage: agent-review.sh <task-id> <reviewer-role> --brief-file <path> [--engine claude|codex]" ;;
  esac
done
valid_task_id "$ID" || die "invalid task id: $ID"
[ -n "$ROLE_NAME" ] || die "usage: agent-review.sh <task-id> <reviewer-role> --brief-file <path> [--engine claude|codex]"
[ -n "$BRIEF_FILE" ] && [ -f "$BRIEF_FILE" ] || die "--brief-file is required and must exist: $BRIEF_FILE"
[ -z "$EXPLICIT_ENGINE" ] || engine_valid "$EXPLICIT_ENGINE" || die "engine must be claude or codex, got: $EXPLICIT_ENGINE"

state_lock_acquire "$ID"
require_tools
META=$(require_meta "$ID")
[ "$(meta_get "$META" stopped)" != 1 ] || die "task agent is stopped; use a relaunch flow"
OLD_NAME=$(meta_get "$META" agent_name); SESSION=$(meta_get "$META" session)
STATE=$(agent_status "$OLD_NAME" "$SESSION")
case "$STATE" in idle|done|blocked) ;; *) die "handoff requires idle, done, or blocked; observed: $STATE" ;; esac
CLEAN_META="$HARNESS_STATE/clean-slate/$ID.meta"
if [ -f "$CLEAN_META" ]; then
  case "$(meta_get "$CLEAN_META" state)" in reviewing|fixing|verifying|publishing) die "Clean Slate is mutating the task; handoff refused" ;; esac
fi
WORKTREE=$(meta_get "$META" worktree); [ -d "$WORKTREE" ] || die "worktree is unavailable: $WORKTREE"
BRANCH=$(git -C "$WORKTREE" branch --show-current); HEAD=$(git -C "$WORKTREE" rev-parse HEAD)
RAW_STATUS=$(git -C "$WORKTREE" status --porcelain)
STATUS=$(printf '%s\n' "$RAW_STATUS" | sed -n '1,80p')
FINGERPRINT=$(printf '%s\n%s\n%s' "$BRANCH" "$HEAD" "$RAW_STATUS" | git hash-object --stdin)

PROJECT=$(meta_get "$META" project)
OLD_AGENT=$(meta_get "$META" agent)
ENGINE=$EXPLICIT_ENGINE; [ -n "$ENGINE" ] || ENGINE=$(meta_get "$META" engine); ENGINE=${ENGINE:-claude}
ROLE=$(role_path "$PROJECT" "$ROLE_NAME")
[ -f "$ROLE" ] || die "role definition not found for $ROLE_NAME (checked projects/$PROJECT/agents/ and agents/)"
GENERATION=$(meta_get "$META" generation); GENERATION=${GENERATION:-1}; GENERATION=$((GENERATION + 1))
BRIEF=$(cat "$BRIEF_FILE")

HARNESS_HERDR_SESSION=$SESSION
LAUNCH=$(engine_start "$ENGINE" "$ID" "$ROLE_NAME" "$ROLE" "$WORKTREE" "$GENERATION") || die "could not start $ROLE_NAME; old agent preserved"
NEW_TAB=$(printf '%s' "$LAUNCH" | jq -r '.tab'); NEW_PANE=$(printf '%s' "$LAUNCH" | jq -r '.pane'); NEW_NAME=$(printf '%s' "$LAUNCH" | jq -r '.name'); NEW_SYSTEM=$(printf '%s' "$LAUNCH" | jq -r '.system'); NEW_WORKSPACE=$(printf '%s' "$LAUNCH" | jq -r '.workspace')
NOW_BRANCH=$(git -C "$WORKTREE" branch --show-current); NOW_HEAD=$(git -C "$WORKTREE" rev-parse HEAD); NOW_STATUS=$(git -C "$WORKTREE" status --porcelain)
NOW_FINGERPRINT=$(printf '%s\n%s\n%s' "$NOW_BRANCH" "$NOW_HEAD" "$NOW_STATUS" | git hash-object --stdin)
if [ "$FINGERPRINT" != "$NOW_FINGERPRINT" ]; then herdr_call tab close "$NEW_TAB" >/dev/null 2>&1 || true; die "worktree changed during handoff; old agent preserved"; fi

BACKUP=$(mktemp "$HARNESS_STATE/.review-backup.XXXXXX"); cp "$META" "$BACKUP"
TMP=$(mktemp "$HARNESS_STATE/.review-meta.XXXXXX")
awk -F= -v agent="$ROLE_NAME" -v engine="$ENGINE" -v generation="$GENERATION" -v name="$NEW_NAME" -v workspace="$NEW_WORKSPACE" -v tab="$NEW_TAB" -v pane="$NEW_PANE" -v system="$NEW_SYSTEM" -v at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
  $1=="agent" {print "agent=" agent; seen_agent=1; next}
  $1=="engine" {print "engine=" engine; seen_engine=1; next}
  $1=="generation" {print "generation=" generation; seen_generation=1; next}
  $1=="agent_name" {print "agent_name=" name; next}
  $1=="workspace" {print "workspace=" workspace; next}
  $1=="tab" {print "tab=" tab; next}
  $1=="pane" {print "pane=" pane; next}
  $1=="system_prompt" {print "system_prompt=" system; seen_system=1; next}
  {print}
  END {if(!seen_agent) print "agent=" agent; if(!seen_engine) print "engine=" engine; if(!seen_generation) print "generation=" generation; if(!seen_system) print "system_prompt=" system; print "handed_off_at=" at}
' "$META" > "$TMP"; chmod 600 "$TMP"; mv "$TMP" "$META"

if ! engine_prompt "$ENGINE" "$NEW_NAME" "$NEW_SYSTEM" "$BRIEF"; then
  mv "$BACKUP" "$META"; herdr_call tab close "$NEW_TAB" >/dev/null 2>&1 || true; die "review prompt failed; old binding restored"
fi
OLD_TAB=$(meta_get "$BACKUP" tab)
rm "$BACKUP"
HISTORY_DIR="$HARNESS_STATE/agent-history"; mkdir -p "$HISTORY_DIR"
jq -nc --arg task "$ID" --arg from "$OLD_AGENT" --arg to "$ROLE_NAME" --arg oldAgent "$OLD_NAME" --arg newAgent "$NEW_NAME" --arg head "$HEAD" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  '{schema:"harness-agent-review-handoff.v1",task:$task,from:$from,to:$to,oldAgent:$oldAgent,newAgent:$newAgent,head:$head,at:$at}' >> "$HISTORY_DIR/$ID.jsonl"
[ -z "$OLD_TAB" ] || herdr --session "$SESSION" tab close "$OLD_TAB" >/dev/null 2>&1 || printf 'warning: old tab could not be closed: %s\n' "$OLD_TAB" >&2
printf 'handed off: %s · %s -> %s · generation=%s · worktree=%s\n' "$ID" "$OLD_AGENT" "$ROLE_NAME" "$GENERATION" "$WORKTREE"

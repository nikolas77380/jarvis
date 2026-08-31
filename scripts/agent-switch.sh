#!/usr/bin/env bash
# Hand a stopped-at-a-safe-point task between Claude and Codex in the same worktree.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
# shellcheck source=scripts/agent-engine-lib.sh
. "$HARNESS_ROOT/scripts/agent-engine-lib.sh"

ID=${1:-}; TARGET=${2:-}; shift 2 || true; NOTE=''; RELAUNCH=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --relaunch) RELAUNCH=1; shift ;;
    --note) [ "$#" -ge 2 ] || die 'missing value for --note'; NOTE=$2; shift 2 ;;
    *) die 'usage: agent-switch.sh <task-id> claude|codex [--relaunch] [--note <text>]' ;;
  esac
done
valid_task_id "$ID" || die "invalid task id: $ID"
engine_valid "$TARGET" || die "engine must be claude or codex, got: $TARGET"
state_lock_acquire "$ID"
require_tools
META=$(require_meta "$ID")
[ "$(meta_get "$META" stopped)" != 1 ] || die "task agent is stopped; use a relaunch flow"
CURRENT=$(meta_get "$META" engine); CURRENT=${CURRENT:-claude}
if [ "$CURRENT" = "$TARGET" ] && [ "$RELAUNCH" != 1 ]; then die "task already uses engine=$TARGET (use --relaunch to resume it in a fresh conversation)"; fi
OLD_NAME=$(meta_get "$META" agent_name); SESSION=$(meta_get "$META" session)
STATE=$(agent_status "$OLD_NAME" "$SESSION")
case "$STATE" in
  idle|done|blocked) ;;
  unknown) [ "$RELAUNCH" = 1 ] || die "switch requires idle, done, or blocked; observed: $STATE" ;;
  *) die "switch requires idle, done, or blocked; observed: $STATE" ;;
esac
CLEAN_META="$HARNESS_STATE/clean-slate/$ID.meta"
if [ -f "$CLEAN_META" ]; then
  case "$(meta_get "$CLEAN_META" state)" in reviewing|fixing|verifying|publishing) die "Clean Slate is mutating the task; switch refused" ;; esac
fi
WORKTREE=$(meta_get "$META" worktree); [ -d "$WORKTREE" ] || die "worktree is unavailable: $WORKTREE"
BRANCH=$(git -C "$WORKTREE" branch --show-current); HEAD=$(git -C "$WORKTREE" rev-parse HEAD)
RAW_STATUS=$(git -C "$WORKTREE" status --porcelain)
STATUS=$(printf '%s\n' "$RAW_STATUS" | sed -n '1,80p')
FINGERPRINT=$(printf '%s\n%s\n%s' "$BRANCH" "$HEAD" "$RAW_STATUS" | git hash-object --stdin)
AGENT=$(meta_get "$META" agent); PROJECT=$(meta_get "$META" project); ROLE=$(role_path "$PROJECT" "$AGENT")
[ -f "$ROLE" ] || die "role definition not found for $AGENT (checked projects/$PROJECT/agents/ and agents/)"
CARD=$(task_card "$ID"); BRIEF=$(card_brief "$CARD"); GENERATION=$(meta_get "$META" generation); GENERATION=${GENERATION:-1}; GENERATION=$((GENERATION + 1))
HARNESS_HERDR_SESSION=$SESSION
LAUNCH=$(engine_start "$TARGET" "$ID" "$AGENT" "$ROLE" "$WORKTREE" "$GENERATION") || die "could not start target engine=$TARGET; old agent preserved"
NEW_TAB=$(printf '%s' "$LAUNCH" | jq -r '.tab'); NEW_PANE=$(printf '%s' "$LAUNCH" | jq -r '.pane'); NEW_NAME=$(printf '%s' "$LAUNCH" | jq -r '.name'); NEW_SYSTEM=$(printf '%s' "$LAUNCH" | jq -r '.system'); NEW_WORKSPACE=$(printf '%s' "$LAUNCH" | jq -r '.workspace')
NOW_BRANCH=$(git -C "$WORKTREE" branch --show-current); NOW_HEAD=$(git -C "$WORKTREE" rev-parse HEAD); NOW_STATUS=$(git -C "$WORKTREE" status --porcelain)
NOW_FINGERPRINT=$(printf '%s\n%s\n%s' "$NOW_BRANCH" "$NOW_HEAD" "$NOW_STATUS" | git hash-object --stdin)
if [ "$FINGERPRINT" != "$NOW_FINGERPRINT" ]; then herdr_call tab close "$NEW_TAB" >/dev/null 2>&1 || true; die "worktree changed during switch; old agent preserved"; fi
HANDOFF=$(cat <<EOF
# Engine handoff

Continue task $ID in the existing worktree. Previous engine: $CURRENT. Current engine: $TARGET.
Branch: $BRANCH. HEAD: $HEAD. Runtime state before handoff: $STATE.

## Original brief

$BRIEF

## Git status at handoff

${STATUS:-(clean)}

## Jarvis/orchestrator note

${NOTE:-(none)}
EOF
)
BACKUP=$(mktemp "$HARNESS_STATE/.switch-backup.XXXXXX"); cp "$META" "$BACKUP"
TMP=$(mktemp "$HARNESS_STATE/.switch-meta.XXXXXX")
awk -F= -v engine="$TARGET" -v generation="$GENERATION" -v name="$NEW_NAME" -v workspace="$NEW_WORKSPACE" -v tab="$NEW_TAB" -v pane="$NEW_PANE" -v system="$NEW_SYSTEM" -v at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
  $1=="engine" {print "engine=" engine; seen_engine=1; next}
  $1=="generation" {print "generation=" generation; seen_generation=1; next}
  $1=="agent_name" {print "agent_name=" name; next}
  $1=="workspace" {print "workspace=" workspace; next}
  $1=="tab" {print "tab=" tab; next}
  $1=="pane" {print "pane=" pane; next}
  $1=="system_prompt" {print "system_prompt=" system; seen_system=1; next}
  {print}
  END {if(!seen_engine) print "engine=" engine; if(!seen_generation) print "generation=" generation; if(!seen_system) print "system_prompt=" system; print "switched_at=" at}
' "$META" > "$TMP"; chmod 600 "$TMP"; mv "$TMP" "$META"
if ! engine_prompt "$TARGET" "$NEW_NAME" "$NEW_SYSTEM" "$HANDOFF"; then
  mv "$BACKUP" "$META"; herdr_call tab close "$NEW_TAB" >/dev/null 2>&1 || true; die "target prompt failed; old binding restored"
fi
OLD_TAB=$(meta_get "$BACKUP" tab)
rm "$BACKUP"
HISTORY_DIR="$HARNESS_STATE/agent-history"; mkdir -p "$HISTORY_DIR"
jq -nc --arg task "$ID" --arg from "$CURRENT" --arg to "$TARGET" --arg oldAgent "$OLD_NAME" --arg newAgent "$NEW_NAME" --arg head "$HEAD" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg note "$NOTE" \
  '{schema:"harness-agent-switch.v1",task:$task,from:$from,to:$to,oldAgent:$oldAgent,newAgent:$newAgent,head:$head,note:$note,switchedAt:$at}' >> "$HISTORY_DIR/$ID.jsonl"
[ -z "$OLD_TAB" ] || herdr --session "$SESSION" tab close "$OLD_TAB" >/dev/null 2>&1 || printf 'warning: old tab could not be closed: %s\n' "$OLD_TAB" >&2
printf 'switched: %s · %s -> %s · generation=%s · worktree=%s\n' "$ID" "$CURRENT" "$TARGET" "$GENERATION" "$WORKTREE"

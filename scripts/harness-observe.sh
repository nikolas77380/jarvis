#!/usr/bin/env bash
# Emit one local, read-only observation for a recorded task.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"

ID=${1:-}
[ "$#" -eq 1 ] || die "usage: harness-observe.sh <task-id>"
valid_task_id "$ID" || die "invalid task id: $ID"
command -v jq >/dev/null || die "jq is required"

META=$(task_meta "$ID")
ARCHIVE_META="$HARNESS_STATE/archive/$ID/runtime.original.meta"
CARD_COUNT=$(find "$HARNESS_ROOT/plan" -maxdepth 1 -type f -name "$ID*.md" ! -name TEMPLATE.md 2>/dev/null | wc -l | tr -d ' ')
CARD_EXISTS=false
[ "$CARD_COUNT" = 1 ] && CARD_EXISTS=true
ISSUES_FILE=$(mktemp)
trap 'rm -f "$ISSUES_FILE"' EXIT
issue() { printf '%s\n' "$1" >> "$ISSUES_FILE"; }

META_VALID=false
ARCHIVED=false
PROJECT='' AGENT='' WORKTREE='' RECORDED_BRANCH='' OBSERVED=missing ACTUAL_BRANCH='' HEAD='' CLEAN=false
if { [ ! -f "$META" ] || [ -L "$META" ]; } && [ -f "$ARCHIVE_META" ] && [ ! -L "$ARCHIVE_META" ]; then
  META=$ARCHIVE_META
  ARCHIVED=true
fi
if [ ! -f "$META" ] || [ -L "$META" ]; then
  issue runtime-metadata-missing
elif [ "$(meta_get "$META" schema)" != harness-herdr-task.v1 ]; then
  issue malformed-metadata
else
  META_VALID=true
  PROJECT=$(meta_get "$META" project)
  AGENT=$(meta_get "$META" agent)
  WORKTREE=$(meta_get "$META" worktree)
  RECORDED_BRANCH=$(meta_get "$META" branch)
  if [ "$ARCHIVED" = true ]; then
    OBSERVED=archived
  elif [ "$(meta_get "$META" stopped)" = 1 ]; then
    OBSERVED=stopped
  else
    OUT=$(herdr --session "$(meta_get "$META" session)" agent get "$(meta_get "$META" agent_name)" 2>/dev/null) || OUT=
    if [ -z "$OUT" ]; then
      OBSERVED=unknown
    elif [ "$(printf '%s' "$OUT" | jq -r '.result.agent // empty')" = "" ]; then
      OBSERVED=missing
      issue runtime-agent-missing
    else
      OBSERVED=$(printf '%s' "$OUT" | jq -r '.result.agent.agent_status // "unknown"')
    fi
  fi
  if [ "$ARCHIVED" = true ]; then
    CLEAN=true
  elif [ ! -d "$WORKTREE" ]; then
    issue worktree-missing
  elif ! git -C "$WORKTREE" rev-parse --git-dir >/dev/null 2>&1; then
    issue worktree-not-git
  else
    ACTUAL_BRANCH=$(git -C "$WORKTREE" branch --show-current)
    HEAD=$(git -C "$WORKTREE" rev-parse HEAD)
    [ -z "$(git -C "$WORKTREE" status --porcelain)" ] && CLEAN=true
    [ "$ACTUAL_BRANCH" = "$RECORDED_BRANCH" ] || issue branch-mismatch
  fi
fi
[ "$CARD_EXISTS" = true ] || issue card-missing

CLEAN_STATE=none
CLEAN_META="$HARNESS_STATE/clean-slate/$ID.meta"
if [ "$ARCHIVED" = true ]; then CLEAN_META="$HARNESS_STATE/archive/$ID/clean-slate.original.meta"; fi
if [ -f "$CLEAN_META" ]; then
  if [ "$(meta_get "$CLEAN_META" schema)" = harness-clean-slate.v1 ]; then
    CLEAN_STATE=$(meta_get "$CLEAN_META" state)
    CLEAN_HEAD=$(meta_get "$CLEAN_META" head)
    case "$CLEAN_STATE" in ready|aborted|failed) ;; *) [ -z "$HEAD" ] || [ "$CLEAN_HEAD" = "$HEAD" ] || issue clean-slate-head-mismatch ;; esac
  else
    CLEAN_STATE=malformed
    issue malformed-clean-slate-metadata
  fi
fi

ISSUES=$(jq -R . "$ISSUES_FILE" | jq -s .)
jq -n --arg schema harness-task-observation.v1 --arg task "$ID" --arg project "$PROJECT" \
  --arg agent "$AGENT" --arg observed "$OBSERVED" --arg worktree "$WORKTREE" \
  --arg recordedBranch "$RECORDED_BRANCH" --arg branch "$ACTUAL_BRANCH" --arg head "$HEAD" \
  --arg cleanState "$CLEAN_STATE" --argjson cardExists "$CARD_EXISTS" --argjson metadataValid "$META_VALID" \
  --argjson clean "$CLEAN" --argjson issues "$ISSUES" \
  '{schema:$schema,task:$task,project:$project,agent:$agent,card:{exists:$cardExists},runtime:{metadataValid:$metadataValid,observed:$observed},worktree:{path:$worktree,exists:($worktree != "" and $head != ""),clean:$clean,recordedBranch:$recordedBranch,branch:$branch,head:$head},cleanSlate:{state:$cleanState},issues:$issues,consistent:($issues|length==0),nextAction:(if ($issues|length)>0 then "inspect" elif $observed=="working" then "wait" elif $observed=="archived" then "none" else "continue" end)}'

#!/usr/bin/env bash
# Archive a completed task and remove only its recorded worktree. Never delete its branch.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"

ID=${1:-}
MODE=${2:-}
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || { [ -n "$MODE" ] && [ "$MODE" != --execute ]; }; then
  die 'usage: task-teardown.sh <task-id> [--execute]'
fi
valid_task_id "$ID" || die "invalid task id: $ID"
[ "$MODE" != --execute ] || state_lock_acquire "$ID"
command -v git >/dev/null 2>&1 || die "git is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

META=$(require_meta "$ID")
CARD=$(task_card "$ID")
[ "$(card_field "$CARD" Status)" = "done" ] || die "task card status must be done before teardown"
PROJECT=$(meta_get "$META" project)
PROJECT_ROOT=$(meta_get "$META" project_root)
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT=$(project_root_path "$PROJECT")
WORKTREE=$(meta_get "$META" worktree)
BRANCH=$(meta_get "$META" branch)
CLEAN_META="$HARNESS_STATE/clean-slate/$ID.meta"
ARCHIVE="$HARNESS_STATE/archive/$ID"

[ -d "$PROJECT_ROOT" ] || die "project root is unavailable: $PROJECT_ROOT"
[ -d "$WORKTREE" ] || die "worktree is unavailable: $WORKTREE"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd -P)
WORKTREE=$(cd "$WORKTREE" && pwd -P)
[ -z "$(git -C "$WORKTREE" status --porcelain -- . ':(exclude).clean-slate')" ] || die "worktree is dirty: $WORKTREE"
[ "$(git -C "$WORKTREE" branch --show-current)" = "$BRANCH" ] || die "recorded branch does not match worktree"
git -C "$PROJECT_ROOT" worktree list --porcelain | grep -qxF "worktree $WORKTREE" \
  || die "worktree is not registered by project: $WORKTREE"
[ "$(meta_get "$META" stopped)" = 1 ] || die "task agent must be stopped before teardown"
[ -f "$CLEAN_META" ] && [ ! -L "$CLEAN_META" ] || die "Clean Slate metadata is required before teardown"
[ "$(meta_get "$CLEAN_META" schema)" = harness-clean-slate.v1 ] || die "Clean Slate metadata is malformed"
CLEAN_STATE=$(meta_get "$CLEAN_META" state)
case "$CLEAN_STATE" in ready|aborted) ;; *) die "Clean Slate must be ready or aborted, got: $CLEAN_STATE" ;; esac
[ ! -e "$ARCHIVE" ] || die "task archive already exists: $ARCHIVE"

CONFIG="$HARNESS_ROOT/config/projects/$PROJECT.json"
PUBLISHED=false
if [ -f "$CONFIG" ] && [ "$(jq -r 'if has("publish") then .publish else true end' "$CONFIG")" = false ]; then
  PUBLISHED=true
elif [ -n "$(meta_get "$CLEAN_META" pr)" ]; then
  PUBLISHED=true
elif UPSTREAM=$(git -C "$WORKTREE" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
  [ "$(git -C "$WORKTREE" rev-list --count "$UPSTREAM..HEAD")" = 0 ] && PUBLISHED=true
fi
[ "$PUBLISHED" = true ] || die "branch has no proven published outcome"

if [ "$MODE" != --execute ]; then
  printf 'teardown: %s · eligible=true · execute=false · worktree=%s · branch-preserved=%s\n' "$ID" "$WORKTREE" "$BRANCH"
  exit 0
fi

mkdir -p "$ARCHIVE"
cp "$META" "$ARCHIVE/runtime.meta"
cp "$CLEAN_META" "$ARCHIVE/clean-slate.meta"
RUN_DIR=$(meta_get "$CLEAN_META" run_dir)
if [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ]; then mv "$RUN_DIR" "$ARCHIVE/artifacts"; fi

for KEY in review_tab fix_tab; do
  TAB=$(meta_get "$CLEAN_META" "$KEY")
  if [ -n "$TAB" ] && ! herdr --session "$(meta_get "$META" session)" tab close "$TAB" >/dev/null 2>&1; then
    printf 'warning: recorded Clean Slate tab could not be closed: %s\n' "$TAB" >&2
  fi
done
git -C "$PROJECT_ROOT" worktree remove "$WORKTREE" || die "could not remove worktree; archive preserved at $ARCHIVE"
mv "$META" "$ARCHIVE/runtime.original.meta"
mv "$CLEAN_META" "$ARCHIVE/clean-slate.original.meta"
printf 'teardown: %s · removed=true · worktree=%s · branch-preserved=%s · archive=%s\n' "$ID" "$WORKTREE" "$BRANCH" "$ARCHIVE"

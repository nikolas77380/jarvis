#!/usr/bin/env bash
# Create an isolated worktree and start its declared task in a background Herdr tab.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
. "$HARNESS_ROOT/scripts/agent-engine-lib.sh"

ID=${1:-}
[ "$#" -ge 1 ] || die "usage: agent-spawn.sh <task-id> [--engine claude|codex]"
shift
EXPLICIT_ENGINE=''
if [ "$#" -gt 0 ]; then [ "$#" -eq 2 ] && [ "$1" = --engine ] || die "usage: agent-spawn.sh <task-id> [--engine claude|codex]"; EXPLICIT_ENGINE=$2; fi
valid_task_id "$ID" || die "invalid task id: $ID"
state_lock_acquire "$ID"
require_tools

CARD=$(task_card "$ID")
AGENT=$(card_field "$CARD" Owner)
PROJECT=$(card_project "$CARD")
ENGINE=$(engine_resolve "$EXPLICIT_ENGINE" "$CARD" "$PROJECT")
case "$AGENT" in ''|*[!a-zA-Z0-9._-]*) die "task card has an invalid Owner: $AGENT" ;; esac
case "$PROJECT" in ''|*[!a-zA-Z0-9._-]*) die "task card has an invalid Project: $PROJECT" ;; esac
PROJECT_ROOT=$(project_root_path "$PROJECT")
[ -d "$PROJECT_ROOT/.git" ] || [ -f "$PROJECT_ROOT/.git" ] \
  || die "project clone is unavailable: $PROJECT_ROOT"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd -P)
ROLE=$(role_path "$PROJECT" "$AGENT")
[ -f "$ROLE" ] || die "role definition not found for $AGENT (checked projects/$PROJECT/agents/ and agents/)"
META=$(task_meta "$ID")
if [ -f "$META" ] && [ ! -L "$META" ]; then
  OLD_NAME=$(meta_get "$META" agent_name)
  OLD_STOPPED=$(meta_get "$META" stopped)
  if [ "$OLD_STOPPED" != 1 ] && [ -n "$OLD_NAME" ] \
    && [ "$(agent_status "$OLD_NAME" "$(meta_get "$META" session)")" != unknown ]; then
    die "task $ID already has a live Herdr agent ($OLD_NAME)"
  fi
  die "task $ID already has runtime metadata; reconcile or teardown it before respawning"
fi

BRIEF=$(card_brief "$CARD")
[ -n "$BRIEF" ] || die "task card has no non-empty ## Brief section: $CARD"
mkdir -p "$HARNESS_WORKTREES/$PROJECT"
WORKTREE="$HARNESS_WORKTREES/$PROJECT/$ID"
[ ! -e "$WORKTREE" ] || die "worktree path already exists: $WORKTREE"
BRANCH="harness/$ID"
git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" && die "branch already exists: $BRANCH"
git -C "$PROJECT_ROOT" worktree add -q -b "$BRANCH" "$WORKTREE" HEAD \
  || die "could not create worktree for $ID"

cleanup_failed_spawn() {
  [ -z "${TAB:-}" ] || herdr_call tab close "$TAB" >/dev/null 2>&1 || true
  echo "error: Herdr spawn failed; worktree preserved at $WORKTREE" >&2
}
trap cleanup_failed_spawn ERR HUP INT TERM

LAUNCH=$(engine_start "$ENGINE" "$ID" "$AGENT" "$ROLE" "$WORKTREE" 1) || die "could not start $ENGINE agent"
TAB=$(printf '%s' "$LAUNCH" | jq -r '.tab'); PANE=$(printf '%s' "$LAUNCH" | jq -r '.pane')
WORKSPACE=$(printf '%s' "$LAUNCH" | jq -r '.workspace'); RUNTIME_NAME=$(printf '%s' "$LAUNCH" | jq -r '.name')
SYSTEM_PROMPT=$(printf '%s' "$LAUNCH" | jq -r '.system')
engine_prompt "$ENGINE" "$RUNTIME_NAME" "$SYSTEM_PROMPT" "$BRIEF" || die "could not prompt $ENGINE agent; worktree preserved for reconciliation"

atomic_meta_write "$META" <<EOF
schema=harness-herdr-task.v1
task=$ID
card=${CARD#"$HARNESS_ROOT"/}
project=$PROJECT
project_root=$PROJECT_ROOT
agent=$AGENT
agent_name=$RUNTIME_NAME
engine=$ENGINE
generation=1
session=$HARNESS_HERDR_SESSION
workspace=$WORKSPACE
tab=$TAB
pane=$PANE
system_prompt=$SYSTEM_PROMPT
worktree=$WORKTREE
branch=$BRANCH
started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
stopped=0
EOF
trap - ERR HUP INT TERM
printf 'spawned: %s · agent=%s · herdr=%s:%s · worktree=%s\n' "$ID" "$AGENT" "$HARNESS_HERDR_SESSION" "$PANE" "$WORKTREE"

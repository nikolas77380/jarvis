#!/usr/bin/env bash
# Create an isolated worktree and start its declared task in a background Herdr tab.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"

ID=${1:-}
[ "$#" -eq 1 ] || die "usage: agent-spawn.sh <task-id>"
valid_task_id "$ID" || die "invalid task id: $ID"
require_tools

CARD=$(task_card "$ID")
AGENT=$(card_field "$CARD" Owner)
PROJECT=$(card_field "$CARD" Project)
case "$AGENT" in ''|*[!a-zA-Z0-9._-]*) die "task card has an invalid Owner: $AGENT" ;; esac
case "$PROJECT" in ''|*[!a-zA-Z0-9._-]*) die "task card has an invalid Project: $PROJECT" ;; esac
PROJECT_ROOT="$HARNESS_ROOT/projects/$PROJECT"
[ -d "$PROJECT_ROOT/.git" ] || [ -f "$PROJECT_ROOT/.git" ] \
  || die "project clone is unavailable: $PROJECT_ROOT"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd -P)
ROLE="$HARNESS_ROOT/agents/$AGENT.md"
[ -f "$ROLE" ] || die "central role definition not found: $ROLE"
MODEL=$(role_field "$ROLE" model)
EFFORT=$(role_field "$ROLE" effort)
META=$(task_meta "$ID")
RUNTIME_NAME=$(agent_runtime_name "$ID")
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

WORKSPACE=$(workspace_ensure)
OUT=$(herdr_call tab create --workspace "$WORKSPACE" --cwd "$WORKTREE" --label "$ID" --no-focus)
TAB=$(printf '%s' "$OUT" | jq -er '.result.tab.tab_id')
PANE=$(printf '%s' "$OUT" | jq -er '.result.root_pane.pane_id')

SYSTEM_PROMPT="$HARNESS_STATE/$ID.system.md"
{
  printf '# Central harness rules\n\n'
  cat "$HARNESS_ROOT/RULES.md"
  printf '\n\n# Assigned role: %s\n\n' "$AGENT"
  cat "$ROLE"
  if [ ! -f "$WORKTREE/CLAUDE.md" ] && [ -f "$WORKTREE/AGENTS.md" ]; then
    printf '\n\n# Project instructions (AGENTS.md)\n\n'
    cat "$WORKTREE/AGENTS.md"
  fi
} > "$SYSTEM_PROMPT"
chmod 600 "$SYSTEM_PROMPT"
CLAUDE_ARGS=(--append-system-prompt-file "$SYSTEM_PROMPT" --name "$ID" --permission-mode auto)
[ -z "$MODEL" ] || CLAUDE_ARGS+=(--model "$MODEL")
[ -z "$EFFORT" ] || CLAUDE_ARGS+=(--effort "$EFFORT")
herdr_call agent start "$RUNTIME_NAME" --kind claude --pane "$PANE" -- "${CLAUDE_ARGS[@]}" >/dev/null
herdr_call agent prompt "$RUNTIME_NAME" "$BRIEF" >/dev/null

atomic_meta_write "$META" <<EOF
schema=harness-herdr-task.v1
task=$ID
card=${CARD#"$HARNESS_ROOT"/}
project=$PROJECT
project_root=$PROJECT_ROOT
agent=$AGENT
agent_name=$RUNTIME_NAME
session=$HARNESS_HERDR_SESSION
workspace=$WORKSPACE
tab=$TAB
pane=$PANE
worktree=$WORKTREE
branch=$BRANCH
started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
stopped=0
EOF
trap - ERR HUP INT TERM
printf 'spawned: %s · agent=%s · herdr=%s:%s · worktree=%s\n' "$ID" "$AGENT" "$HARNESS_HERDR_SESSION" "$PANE" "$WORKTREE"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/harness"
PROJECT="$REPO/projects/demo"
WORKTREE="$REPO/worktrees/task-one"
mkdir -p "$REPO/scripts" "$PROJECT/plan" "$REPO/.harness-state/clean-slate" "$REPO/config/projects" "$REPO/worktrees" "$PROJECT"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/task-teardown.sh" "$REPO/scripts/"
cp "$ROOT/scripts/harness-observe.sh" "$ROOT/scripts/fleet-snapshot.sh" "$ROOT/scripts/harness-doctor.sh" "$REPO/scripts/"

git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email test@example.com
git -C "$PROJECT" config user.name Test
printf '# demo\n' > "$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" commit -qm initial
git -C "$PROJECT" worktree add -q -b harness/task-one "$WORKTREE" HEAD

cat > "$PROJECT/plan/task-one.md" <<'CARD'
# Task one
**Status:** done · **Owner:** engineer
CARD
cat > "$REPO/.harness-state/task-one.meta" <<EOF
schema=harness-herdr-task.v1
task=task-one
project=demo
project_root=$PROJECT
agent=engineer
agent_name=h_task
session=test
tab=w1:t1
worktree=$WORKTREE
branch=harness/task-one
stopped=1
EOF
cat > "$REPO/.harness-state/clean-slate/task-one.meta" <<EOF
schema=harness-clean-slate.v1
task=task-one
state=ready
run_dir=$WORKTREE/.clean-slate/task-one
EOF
mkdir -p "$WORKTREE/.clean-slate/task-one"
printf 'evidence\n' > "$WORKTREE/.clean-slate/task-one/events.log"
cat > "$REPO/config/projects/demo.json" <<'JSON'
{"baseBranch":"master","publish":false,"checks":[]}
JSON

export HARNESS_STATE_DIR="$REPO/.harness-state"
"$REPO/scripts/task-teardown.sh" task-one | grep -q 'eligible=true'
test -d "$WORKTREE"

printf 'dirty\n' >> "$WORKTREE/README.md"
if "$REPO/scripts/task-teardown.sh" task-one --execute >/dev/null 2>&1; then
  echo 'dirty teardown unexpectedly succeeded' >&2
  exit 1
fi
git -C "$WORKTREE" restore README.md

"$REPO/scripts/task-teardown.sh" task-one --execute | grep -q 'removed=true'
test ! -e "$WORKTREE"
test -f "$REPO/.harness-state/archive/task-one/runtime.meta"
test -f "$REPO/.harness-state/archive/task-one/clean-slate.meta"
test -f "$REPO/.harness-state/archive/task-one/artifacts/events.log"
git -C "$PROJECT" show-ref --verify --quiet refs/heads/harness/task-one
test ! -e "$REPO/.harness-state/task-one.meta"
"$REPO/scripts/harness-observe.sh" task-one | jq -e '.consistent and .runtime.observed == "archived" and .nextAction == "none"' >/dev/null
"$REPO/scripts/harness-doctor.sh" --json | jq -e '.healthy' >/dev/null

# --- finding 4: legacy metadata with no project_root must resolve via project_root_path(), not the
#     hardcoded projects/$PROJECT fallback — which for the reserved root project "jarvis" points at
#     a nonexistent projects/jarvis and dies ---

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
mkdir -p "$REPO/plan"
printf '# root task\n**Status:** done · **Owner:** shell-engineer\n' > "$REPO/plan/root-task.md"
git -C "$REPO" add plan
git -C "$REPO" commit -qm 'root task card'

ROOT_WORKTREE="$REPO/worktrees/root-task"
git -C "$REPO" worktree add -q -b harness/root-task "$ROOT_WORKTREE" HEAD

cat > "$REPO/.harness-state/root-task.meta" <<EOF
schema=harness-herdr-task.v1
task=root-task
project=jarvis
agent=shell-engineer
agent_name=h_root
session=test
tab=w1:t9
worktree=$ROOT_WORKTREE
branch=harness/root-task
stopped=1
EOF
cat > "$REPO/.harness-state/clean-slate/root-task.meta" <<EOF
schema=harness-clean-slate.v1
task=root-task
state=ready
run_dir=$ROOT_WORKTREE/.clean-slate/root-task
EOF
mkdir -p "$ROOT_WORKTREE/.clean-slate/root-task"
printf 'evidence\n' > "$ROOT_WORKTREE/.clean-slate/root-task/events.log"
cat > "$REPO/config/projects/jarvis.json" <<'JSON'
{"baseBranch":"master","publish":false,"checks":[]}
JSON

"$REPO/scripts/task-teardown.sh" root-task | grep -q 'eligible=true' \
  || { echo 'legacy root task metadata (no project_root) failed to resolve via project_root_path' >&2; exit 1; }
"$REPO/scripts/task-teardown.sh" root-task --execute | grep -q 'removed=true'
test ! -e "$ROOT_WORKTREE"
git -C "$REPO" show-ref --verify --quiet refs/heads/harness/root-task

echo 'task teardown tests: ok'

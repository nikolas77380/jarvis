#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
mkdir -p "$REPO/scripts" "$REPO/plan" "$REPO/projects/demo" "$REPO/.harness-state" "$REPO/config/projects"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$REPO/scripts/"
cp "$ROOT/scripts/clean-slate-protocol.sh" "$REPO/scripts/"

git -C "$REPO/projects/demo" init -q
git -C "$REPO/projects/demo" config user.email test@example.com
git -C "$REPO/projects/demo" config user.name Test
printf '# demo\n' > "$REPO/projects/demo/README.md"
git -C "$REPO/projects/demo" add README.md
git -C "$REPO/projects/demo" commit -qm initial
WORKTREE="$REPO/projects/demo"

cat > "$REPO/plan/task-strict.md" <<'CARD'
# Strict task
**Status:** in-review · **Owner:** engineer · **Project:** demo
**Validation:** strict
CARD
cat > "$REPO/plan/task-direct.md" <<'CARD'
# Direct task
**Status:** in-review · **Owner:** engineer · **Project:** demo
**Validation:** direct
CARD
cat > "$REPO/config/projects/demo.json" <<'JSON'
{"baseBranch":"main","checks":[["sh","-c","printf checked"]]}
JSON

write_task_meta() {
  local id=$1
  cat > "$REPO/.harness-state/$id.meta" <<EOF
schema=harness-herdr-task.v1
task=$id
project=demo
worktree=$WORKTREE
branch=harness/$id
stopped=1
EOF
}
write_task_meta task-strict
write_task_meta task-direct

export HARNESS_STATE_DIR="$REPO/.harness-state"
export HARNESS_CLEAN_SLATE_NO_LAUNCH=1

"$REPO/scripts/clean-slate-protocol.sh" run task-strict | grep -q 'state=reviewing'
test "$("$REPO/scripts/clean-slate-protocol.sh" status task-strict)" = 'clean-slate: task-strict · mode=strict · state=reviewing · round=1'
"$REPO/scripts/clean-slate-protocol.sh" status task-strict --json | jq -e '.schema == "harness-clean-slate.v1" and .state == "reviewing"' >/dev/null

if "$REPO/scripts/clean-slate-protocol.sh" run task-strict >/dev/null 2>&1; then
  echo 'duplicate run unexpectedly succeeded' >&2
  exit 1
fi

"$REPO/scripts/clean-slate-protocol.sh" respond task-strict --action fix | grep -q 'state=fixing'
"$REPO/scripts/clean-slate-protocol.sh" abort task-strict | grep -q 'state=aborted'
"$REPO/scripts/clean-slate-protocol.sh" logs task-strict | grep -q 'run started'

"$REPO/scripts/clean-slate-protocol.sh" run task-direct | grep -q 'state=verifying'

echo 'clean slate protocol tests: ok'

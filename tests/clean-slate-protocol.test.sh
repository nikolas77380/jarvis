#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/plan" "$REPO/agents" "$REPO/projects/demo" "$REPO/.harness-state" "$REPO/config/projects" "$FAKEBIN"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$REPO/scripts/"
cp "$ROOT/scripts/clean-slate-protocol.sh" "$REPO/scripts/"
cp "$ROOT/agents/clean-slate-"*.md "$REPO/agents/"
printf '# rules\n' > "$REPO/RULES.md"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case " $* " in
  *" workspace create "*) printf '%s\n' '{"result":{"workspace":{"workspace_id":"w1"}}}' ;;
  *" tab create "*) printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}' ;;
  *" agent get "*) printf '%s\n' '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

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
cat > "$REPO/plan/task-fail.md" <<'CARD'
# Failing checks
**Status:** in-review · **Owner:** engineer · **Project:** demo
**Validation:** direct
CARD
cat > "$REPO/config/projects/demo.json" <<'JSON'
{"baseBranch":"main","publish":false,"checks":[["sh","-c","printf checked"]]}
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
write_task_meta task-fail

export HARNESS_STATE_DIR="$REPO/.harness-state"
export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"
export HARNESS_HERDR_SESSION=test-clean-slate

"$REPO/scripts/clean-slate-protocol.sh" run task-strict | grep -q 'state=reviewing'
test -f "$WORKTREE/.clean-slate/task-strict/review-1.prompt.md"
grep -q ' agent start ' "$FAKE_HERDR_LOG"
grep -q -- '--model opus --effort high' "$FAKE_HERDR_LOG"
test "$("$REPO/scripts/clean-slate-protocol.sh" status task-strict)" = 'clean-slate: task-strict · mode=strict · state=reviewing · round=1'
"$REPO/scripts/clean-slate-protocol.sh" status task-strict --json | jq -e '.schema == "harness-clean-slate.v1" and .state == "reviewing"' >/dev/null

if "$REPO/scripts/clean-slate-protocol.sh" run task-strict >/dev/null 2>&1; then
  echo 'duplicate run unexpectedly succeeded' >&2
  exit 1
fi

cat > "$WORKTREE/.clean-slate/task-strict/review-1.json" <<'JSON'
{"outcome":"findings","summary":"one actionable issue","findings":[{"id":"R1","class":"actionable","message":"fix it"}]}
JSON
test "$("$REPO/scripts/clean-slate-protocol.sh" status task-strict)" = 'clean-slate: task-strict · mode=strict · state=awaiting-response · round=1'
"$REPO/scripts/clean-slate-protocol.sh" respond task-strict --action fix | grep -q 'state=fixing'
test -f "$WORKTREE/.clean-slate/task-strict/fix-1.prompt.md"
grep -q -- '--model sonnet --effort high' "$FAKE_HERDR_LOG"
HEAD_NOW=$(git -C "$WORKTREE" rev-parse HEAD)
printf '{"outcome":"fixed","newHead":"%s","summary":"fixed"}\n' "$HEAD_NOW" > "$WORKTREE/.clean-slate/task-strict/fix-1.json"
test "$("$REPO/scripts/clean-slate-protocol.sh" status task-strict)" = 'clean-slate: task-strict · mode=strict · state=reviewing · round=2'
grep -q "$HEAD_NOW..HEAD" "$WORKTREE/.clean-slate/task-strict/review-2.prompt.md"
"$REPO/scripts/clean-slate-protocol.sh" abort task-strict | grep -q 'state=aborted'
"$REPO/scripts/clean-slate-protocol.sh" logs task-strict | grep -q 'run started'

"$REPO/scripts/clean-slate-protocol.sh" run task-direct | grep -q 'state=ready'
test "$("$REPO/scripts/clean-slate-protocol.sh" status task-direct)" = 'clean-slate: task-direct · mode=direct · state=ready · round=1'
grep -q 'checked' "$WORKTREE/.clean-slate/task-direct/check-1.log"
test -z "$(git -C "$WORKTREE" status --short)"

cat > "$REPO/config/projects/demo.json" <<'JSON'
{"baseBranch":"main","publish":false,"checks":[["sh","-c","exit 7"]]}
JSON
"$REPO/scripts/clean-slate-protocol.sh" run task-fail | grep -q 'state=failed'
test "$("$REPO/scripts/clean-slate-protocol.sh" status task-fail)" = 'clean-slate: task-fail · mode=direct · state=failed · round=1'

echo 'clean slate protocol tests: ok'

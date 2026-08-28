#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/harness"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/plan" "$REPO/projects/demo" "$REPO/.harness-state" "$FAKEBIN"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$REPO/scripts/"
cp "$ROOT/scripts/harness-observe.sh" "$ROOT/scripts/fleet-snapshot.sh" "$ROOT/scripts/harness-doctor.sh" "$ROOT/scripts/agent-reconcile.sh" "$REPO/scripts/"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
if [ "${FAKE_ENDPOINT:-present}" = missing ]; then
  printf '%s\n' '{"result":{"agent":null}}'
else
  printf '%s\n' '{"result":{"agent":{"agent_status":"idle"}}}'
fi
FAKE
chmod +x "$FAKEBIN/herdr"

git -C "$REPO/projects/demo" init -q
git -C "$REPO/projects/demo" config user.email test@example.com
git -C "$REPO/projects/demo" config user.name Test
printf '# demo\n' > "$REPO/projects/demo/README.md"
git -C "$REPO/projects/demo" add README.md
git -C "$REPO/projects/demo" commit -qm initial
HEAD=$(git -C "$REPO/projects/demo" rev-parse HEAD)

cat > "$REPO/plan/task-ok.md" <<'CARD'
# Task
**Status:** in-review · **Owner:** engineer · **Project:** demo
**Validation:** strict
CARD
cat > "$REPO/plan/task-card-only.md" <<'CARD'
# Missing runtime
**Status:** open · **Owner:** engineer · **Project:** demo
CARD
cat > "$REPO/.harness-state/task-ok.meta" <<EOF
schema=harness-herdr-task.v1
task=task-ok
project=demo
agent=engineer
agent_name=h_task
session=test
worktree=$REPO/projects/demo
branch=master
stopped=1
EOF

export PATH="$FAKEBIN:$PATH"
export HARNESS_STATE_DIR="$REPO/.harness-state"

"$REPO/scripts/harness-observe.sh" task-ok | jq -e \
  '.schema == "harness-task-observation.v1" and .consistent and .worktree.head == $head and .runtime.observed == "stopped"' \
  --arg head "$HEAD" >/dev/null
"$REPO/scripts/fleet-snapshot.sh" --json | jq -e '.schema == "harness-fleet-snapshot.v1" and (.tasks | length) == 2' >/dev/null
if "$REPO/scripts/harness-doctor.sh" --json >/dev/null; then
  echo 'doctor accepted card without runtime' >&2
  exit 1
fi
rm "$REPO/plan/task-card-only.md"
"$REPO/scripts/harness-doctor.sh" --json | jq -e '.healthy and .issueCount == 0' >/dev/null

sed -i.bak 's/^branch=.*/branch=wrong/' "$REPO/.harness-state/task-ok.meta"
rm "$REPO/.harness-state/task-ok.meta.bak"
if "$REPO/scripts/harness-doctor.sh" >/dev/null 2>&1; then
  echo 'doctor accepted branch drift' >&2
  exit 1
fi
"$REPO/scripts/harness-observe.sh" task-ok | jq -e '.issues | index("branch-mismatch")' >/dev/null

sed -i.bak 's/^branch=.*/branch=master/;s/^stopped=.*/stopped=0/' "$REPO/.harness-state/task-ok.meta"
rm "$REPO/.harness-state/task-ok.meta.bak"
FAKE_ENDPOINT=missing "$REPO/scripts/agent-reconcile.sh" task-ok --repair >/dev/null
grep -qx 'stopped=1' "$REPO/.harness-state/task-ok.meta"

echo 'observation tests: ok'

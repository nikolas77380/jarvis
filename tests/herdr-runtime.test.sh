#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/plan" "$REPO/agents" "$REPO/projects/demo" "$REPO/memory/projects" "$FAKEBIN"
cp "$ROOT/scripts/agent-"*.sh "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/harness-state-lib.sh" "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/session-start.sh" "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/harness-observe.sh" "$ROOT/scripts/fleet-snapshot.sh" "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/harness-event-lib.sh" "$ROOT/scripts/events-poll.sh" "$ROOT/scripts/inbox.sh" "$ROOT/scripts/decisions.sh" "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/memory-context.sh" "$REPO/scripts/" 2>/dev/null || true
printf '# Captain\n' > "$REPO/memory/captain.md"
printf '# Harness\n' > "$REPO/memory/harness.md"
printf '# Demo project memory\n' > "$REPO/memory/projects/demo.md"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
args=" $* "
case "$args" in
  *" workspace create "*) printf '%s\n' '{"result":{"workspace":{"workspace_id":"w1"},"tab":{"tab_id":"w1:t0"},"root_pane":{"pane_id":"w1:p0"}}}' ;;
  *" tab create "*) printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}' ;;
  *" agent start "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"idle"}}}' ;;
  *" agent prompt "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"done"}}}' ;;
  *" agent get "*) printf '%s\n' "${FAKE_AGENT_GET:-{\"result\":{\"agent\":{\"agent_status\":\"working\"}}}}" ;;
  *" agent read "*) printf '%s\n' 'agent output line' ;;
  *" tab focus "*|*" tab close "*) printf '%s\n' '{"result":{"ok":true}}' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

cd "$REPO"
git init -q
git config user.email test@example.com
git config user.name Test
printf '%s\n' '# Central rules' > RULES.md
printf '%s\n' '%s' '---' 'model: sonnet' 'effort: high' '---' '# Engineer role' > agents/engineer.md
cat > plan/260828-1200-001-demo.md <<'CARD'
# Demo

**Status:** open · **Owner:** engineer · **Project:** demo · **Blocks:** — · **Depends on:** —
PR: none yet
**Next:** dispatch engineer

## Brief — engineer

Implement the demo and run its checks.

## Done means

The checks pass.
CARD
git add .
git commit -qm initial

git -C projects/demo init -q
git -C projects/demo config user.email test@example.com
git -C projects/demo config user.name Test
printf '%s\n' '# Demo project' > projects/demo/README.md
printf '%s\n' '# Demo project instructions' > projects/demo/AGENTS.md
git -C projects/demo add README.md AGENTS.md
git -C projects/demo commit -qm initial
PROJECT_REAL=$(cd projects/demo && pwd -P)

export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"
export HARNESS_HERDR_SESSION=test-harness

scripts/agent-spawn.sh 260828-1200-001-demo >/dev/null
META=.harness-state/260828-1200-001-demo.meta
test -f "$META"
grep -qx 'schema=harness-herdr-task.v1' "$META"
grep -qx 'session=test-harness' "$META"
grep -qx 'workspace=w1' "$META"
grep -qx 'tab=w1:t2' "$META"
grep -qx 'pane=w1:p2' "$META"
grep -qx 'agent=engineer' "$META"
grep -qx 'project=demo' "$META"
grep -qx "project_root=$PROJECT_REAL" "$META"
grep -q ' tab create ' "$FAKE_HERDR_LOG"
grep -q ' agent start ' "$FAKE_HERDR_LOG"
grep -q -- '--model sonnet --effort high' "$FAKE_HERDR_LOG"
grep -q ' agent prompt ' "$FAKE_HERDR_LOG"
grep -q 'Demo project instructions' .harness-state/260828-1200-001-demo.system.md

if scripts/agent-spawn.sh 260828-1200-001-demo >/dev/null 2>&1; then
  echo 'duplicate spawn unexpectedly succeeded' >&2
  exit 1
fi

test "$(scripts/agent-state.sh 260828-1200-001-demo)" = 'state: working · source: herdr'
test "$(FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"mystery"}}}' scripts/agent-state.sh 260828-1200-001-demo)" = 'state: unknown · source: herdr'
scripts/agent-peek.sh 260828-1200-001-demo 20 | grep -q 'agent output line'
scripts/agent-send.sh 260828-1200-001-demo 'Please continue' >/dev/null
scripts/agent-attach.sh 260828-1200-001-demo >/dev/null
scripts/agent-list.sh | grep -q '260828-1200-001-demo'
SESSION_OUTPUT=$(scripts/session-start.sh)
grep -q '260828-1200-001-demo' <<< "$SESSION_OUTPUT"
SESSION_OUTPUT=$(scripts/session-start.sh --project demo)
grep -q 'Demo project memory' <<< "$SESSION_OUTPUT"

scripts/agent-stop.sh 260828-1200-001-demo >/dev/null
grep -q ' tab close w1:t2' "$FAKE_HERDR_LOG"
grep -qx 'stopped=1' "$META"
test -d "$(sed -n 's/^worktree=//p' "$META")"

echo 'herdr runtime tests: ok'

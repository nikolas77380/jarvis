#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/agents" "$REPO/projects/demo" "$REPO/memory/projects" "$FAKEBIN"
cp "$ROOT/scripts/agent-"*.sh "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/quota-resume-"*.sh "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/harness-state-lib.sh" "$REPO/scripts/" 2>/dev/null || true
cp "$ROOT/scripts/agent-engine-lib.sh" "$ROOT/scripts/agent-switch.sh" "$REPO/scripts/" 2>/dev/null || true
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
  *" agent prompt "*)
    [ "${FAKE_PROMPT_FAIL:-0}" != 1 ] || exit 1
    printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"done"}}}'
    ;;
  *" agent get "*)
    if [ -n "${FAKE_AGENT_GET:-}" ]; then
      printf '%s\n' "$FAKE_AGENT_GET"
    else
      printf '%s\n' '{"result":{"agent":{"agent_status":"working"}}}'
    fi
    ;;
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
git add .
git commit -qm initial

git -C projects/demo init -q
git -C projects/demo config user.email test@example.com
git -C projects/demo config user.name Test
printf '%s\n' '# Demo project' > projects/demo/README.md
printf '%s\n' '# Demo project instructions' > projects/demo/AGENTS.md
mkdir -p projects/demo/plan
cat > projects/demo/plan/260828-1200-001-demo.md <<'CARD'
# Demo

**Status:** open · **Owner:** engineer · **Blocks:** — · **Depends on:** —
**Engine:** claude
PR: none yet
**Next:** dispatch engineer

## Brief — engineer

Implement the demo and run its checks.

## Done means

The checks pass.
CARD
cat > projects/demo/plan/INDEX.md <<'INDEX'
# Plan index

| id | task | status | owner | depends on | note |
|---|---|---|---|---|---|
| [260828-1200-001-demo](260828-1200-001-demo.md) | Demo | open | engineer | — | — |
INDEX
git -C projects/demo add README.md AGENTS.md plan/260828-1200-001-demo.md plan/INDEX.md
git -C projects/demo commit -qm initial
PROJECT_REAL=$(cd projects/demo && pwd -P)

export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"
export HARNESS_HERDR_SESSION=test-harness
export CODEX_HOME="$TMP/user-codex"
mkdir -p "$CODEX_HOME"
printf '%s\n' '{"test":"credentials"}' > "$CODEX_HOME/auth.json"

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
grep -qx 'engine=claude' "$META"
grep -qx 'generation=1' "$META"
grep -qx "project_root=$PROJECT_REAL" "$META"
grep -q ' tab create ' "$FAKE_HERDR_LOG"
grep -q ' agent start ' "$FAKE_HERDR_LOG"
grep -q -- '--model sonnet --effort high' "$FAKE_HERDR_LOG"
grep -q ' agent prompt ' "$FAKE_HERDR_LOG"
SYSTEM_PROMPT=$(sed -n 's/^system_prompt=//p' "$META")
grep -q 'Demo project instructions' "$SYSTEM_PROMPT"

if scripts/agent-spawn.sh 260828-1200-001-demo >/dev/null 2>&1; then
  echo 'duplicate spawn unexpectedly succeeded' >&2
  exit 1
fi

test "$(scripts/agent-state.sh 260828-1200-001-demo)" = 'state: working · source: herdr'
if scripts/agent-switch.sh 260828-1200-001-demo codex >/dev/null 2>&1; then
  echo 'switch while working unexpectedly succeeded' >&2
  exit 1
fi
FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"idle"}}}' scripts/agent-switch.sh 260828-1200-001-demo codex --note 'Continue with Codex' >/dev/null
grep -qx 'engine=codex' "$META"
grep -qx 'generation=2' "$META"
grep -q -- 'agent start .* --kind codex ' "$FAKE_HERDR_LOG"
grep -q -- '--approve-for-me --no-alt-screen' "$FAKE_HERDR_LOG"
if grep -q -- '--ask-for-approval on-request' "$FAKE_HERDR_LOG"; then
  echo 'task-agent codex still requires manual approvals' >&2
  exit 1
fi
grep -q -- 'tab create .* --env HOME=.*/codex-homes/h_.*home --env CODEX_HOME=.*/codex-homes/h_.*state' "$FAKE_HERDR_LOG"
grep -q 'Continue with Codex' "$FAKE_HERDR_LOG"
test "$(wc -l < .harness-state/agent-history/260828-1200-001-demo.jsonl | tr -d ' ')" = 1
mkdir -p .harness-state/quota
cat > .harness-state/quota/260828-1200-001-demo.meta <<'QUOTA'
schema=harness-quota-resume.v1
key=260828-1200-001-demo
kind=task
engine=codex
blocked_reason=quota
resume_at=1
QUOTA
FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"idle"}}}' scripts/quota-resume-poll.sh | grep -q 'quota resumed: 260828-1200-001-demo'
grep -qx 'engine=codex' "$META"
grep -qx 'generation=3' "$META"
test ! -e .harness-state/quota/260828-1200-001-demo.meta
grep -q 'Provider quota reset. Resume automatically' "$FAKE_HERDR_LOG"
OBSERVATION=$(FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"idle"}}}' scripts/harness-observe.sh 260828-1200-001-demo)
test "$(jq -r '.runtime.engine' <<< "$OBSERVATION")" = codex
test "$(jq -r '.runtime.generation' <<< "$OBSERVATION")" = 3
scripts/agent-list.sh | grep -q 'codex.*3'
if FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"done"}}}' FAKE_PROMPT_FAIL=1 scripts/agent-switch.sh 260828-1200-001-demo claude >/dev/null 2>&1; then
  echo 'switch with failed target prompt unexpectedly succeeded' >&2
  exit 1
fi
grep -qx 'engine=codex' "$META"
grep -qx 'generation=3' "$META"
test "$(wc -l < .harness-state/agent-history/260828-1200-001-demo.jsonl | tr -d ' ')" = 2
FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"done"}}}' scripts/agent-switch.sh 260828-1200-001-demo claude >/dev/null
grep -qx 'engine=claude' "$META"
grep -qx 'generation=4' "$META"
test "$(wc -l < .harness-state/agent-history/260828-1200-001-demo.jsonl | tr -d ' ')" = 3
test "$(FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"mystery"}}}' scripts/agent-state.sh 260828-1200-001-demo)" = 'state: unknown · source: herdr'
scripts/agent-peek.sh 260828-1200-001-demo 20 | grep -q 'agent output line'
scripts/agent-send.sh 260828-1200-001-demo 'Please continue' >/dev/null
scripts/agent-attach.sh 260828-1200-001-demo >/dev/null
scripts/agent-list.sh | grep -q '260828-1200-001-demo'
SESSION_OUTPUT=$(scripts/session-start.sh)
grep -q '260828-1200-001-demo' <<< "$SESSION_OUTPUT"
grep -q -- '-- demo --' <<< "$SESSION_OUTPUT"
SESSION_OUTPUT=$(scripts/session-start.sh --project demo)
grep -q 'Demo project memory' <<< "$SESSION_OUTPUT"
grep -q '260828-1200-001-demo' <<< "$SESSION_OUTPUT"

scripts/agent-stop.sh 260828-1200-001-demo >/dev/null
grep -q ' tab close w1:t2' "$FAKE_HERDR_LOG"
grep -qx 'stopped=1' "$META"
test -d "$(sed -n 's/^worktree=//p' "$META")"

echo 'herdr runtime tests: ok'

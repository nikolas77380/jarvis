#!/usr/bin/env bash
# agent-review.sh (engineer -> reviewer handoff) and agent-switch.sh (engine switch) must run the
# same capability preflight on the freshly started session BEFORE delivering the substantive brief /
# handoff note, and must leave the OLD agent/meta fully in place — never partially rebound — when the
# probe fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/agents" "$REPO/projects/demo/plan" "$FAKEBIN"
cp "$ROOT/scripts/agent-"*.sh "$REPO/scripts/" 2>/dev/null
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/agent-engine-lib.sh" "$REPO/scripts/"
cp "$ROOT/scripts/quota-resume-"*.sh "$REPO/scripts/" 2>/dev/null || true

FAKE_AGENT_GET_DEFAULT='{"result":{"agent":{"agent_status":"idle"}}}'
export FAKE_AGENT_GET_DEFAULT
cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case " $* " in
  *" workspace create "*) printf '%s\n' '{"result":{"workspace":{"workspace_id":"w1"}}}' ;;
  *" tab create "*) printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}' ;;
  *" agent start "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"idle"}}}' ;;
  *" agent prompt "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"done"}}}' ;;
  *" agent get "*) printf '%s\n' "${FAKE_AGENT_GET:-$FAKE_AGENT_GET_DEFAULT}" ;;
  *" agent wait "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"idle"}}}' ;;
  *" agent read "*) printf 'CAPABILITY_PREFLIGHT_RESULT %s\n' "${FAKE_CAPABILITY_RESULT:-PASS}" ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

cd "$REPO"
printf '%s\n' '# rules' > RULES.md
printf '%s\n' '---' 'model: sonnet' '---' 'ENGINEER-ROLE' > agents/engineer.md
printf '%s\n' '---' 'model: sonnet' 'capabilities: figma' '---' 'DESIGN-QA-ROLE' > agents/design-qa.md

git -C projects/demo init -q
git -C projects/demo config user.email test@example.com
git -C projects/demo config user.name Test
printf '# demo\n' > projects/demo/README.md
git -C projects/demo add README.md
git -C projects/demo commit -qm initial
cat > projects/demo/plan/task-h.md <<'CARD'
# Task h
**Status:** open · **Owner:** engineer
**Next:** dispatch

## Brief

Engineer brief.
CARD

export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"
export HARNESS_HERDR_SESSION=test-harness

scripts/agent-spawn.sh task-h >/dev/null
META=.harness-state/task-h.meta
OLD_AGENT_NAME=$(sed -n 's/^agent_name=//p' "$META")

printf 'Reviewer brief, SUBSTANTIVE-MARKER.\n' > "$TMP/review-brief.md"

: > "$FAKE_HERDR_LOG"
FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"idle"}}}' FAKE_CAPABILITY_RESULT='FAIL figma' \
  scripts/agent-review.sh task-h design-qa --brief-file "$TMP/review-brief.md" >/dev/null 2>"$TMP/stderr" \
  && { echo "handoff should have failed when the design-qa capability probe fails" >&2; exit 1; }
grep -q 'capability preflight failed' "$TMP/stderr" || { echo "expected a capability-preflight failure message" >&2; cat "$TMP/stderr" >&2; exit 1; }
if grep -q 'SUBSTANTIVE-MARKER' "$FAKE_HERDR_LOG"; then
  echo "the substantive reviewer brief must never be delivered when the probe fails" >&2
  exit 1
fi
grep -qx "agent=engineer" "$META" || { echo "meta must still show the OLD agent after a failed handoff" >&2; exit 1; }
grep -q "agent_name=$OLD_AGENT_NAME" "$META" || { echo "meta must still point at the OLD agent_name after a failed handoff" >&2; exit 1; }

: > "$FAKE_HERDR_LOG"
FAKE_AGENT_GET='{"result":{"agent":{"agent_status":"idle"}}}' FAKE_CAPABILITY_RESULT='PASS' \
  scripts/agent-review.sh task-h design-qa --brief-file "$TMP/review-brief.md" >/dev/null
grep -q 'SUBSTANTIVE-MARKER' "$FAKE_HERDR_LOG" || { echo "the substantive reviewer brief must be delivered once the probe passes" >&2; exit 1; }
grep -qx 'agent=design-qa' "$META" || { echo "meta should show design-qa after a successful handoff" >&2; exit 1; }

echo 'capability preflight handoff tests: ok'

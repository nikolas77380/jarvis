#!/usr/bin/env bash
# End-to-end: a role declaring required capabilities gets a deterministic preflight probe BEFORE its
# substantive brief, on the freshly started session, and a failed (or absent) probe stops the run
# fail-closed — the brief must never reach the agent, and the task must not be recorded as dispatched.
# A role with no declared capabilities is unaffected: no probe, brief delivered as before.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_case() {
  local capability_result=$1
  local TMP REPO FAKEBIN
  TMP="$(mktemp -d)"
  REPO="$TMP/repo"
  FAKEBIN="$TMP/bin"
  mkdir -p "$REPO/scripts" "$REPO/agents" "$REPO/projects/demo/plan" "$FAKEBIN"
  cp "$ROOT/scripts/agent-spawn.sh" "$ROOT/scripts/agent-engine-lib.sh" "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$REPO/scripts/"

  cat > "$FAKEBIN/herdr" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
: "\${FAKE_HERDR_LOG:?}"
printf '%s\n' "\$*" >> "\$FAKE_HERDR_LOG"
case " \$* " in
  *" workspace create "*) printf '%s\n' '{"result":{"workspace":{"workspace_id":"w1"}}}' ;;
  *" tab create "*) printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}' ;;
  *" agent start "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"idle"}}}' ;;
  *" agent prompt "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"done"}}}' ;;
  *" agent wait "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"idle"}}}' ;;
  *" agent read "*) printf 'CAPABILITY_PREFLIGHT_RESULT $capability_result\n' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
  chmod +x "$FAKEBIN/herdr"

  cd "$REPO"
  printf '%s\n' '# rules' > RULES.md
  printf '%s\n' '---' 'model: sonnet' 'capabilities: figma' '---' 'CAPABILITY-ROLE' > agents/design-qa.md

  git -C projects/demo init -q
  git -C projects/demo config user.email test@example.com
  git -C projects/demo config user.name Test
  printf '# demo\n' > projects/demo/README.md
  git -C projects/demo add README.md
  git -C projects/demo commit -qm initial
  cat > projects/demo/plan/task-cap.md <<'CARD'
# Task cap
**Status:** open · **Owner:** design-qa
**Next:** dispatch

## Brief

SUBSTANTIVE-BRIEF-MARKER do the design-qa thing.
CARD

  export PATH="$FAKEBIN:$PATH"
  export FAKE_HERDR_LOG="$TMP/herdr.log"
  export HARNESS_HERDR_SESSION=test-harness

  local rc=0
  scripts/agent-spawn.sh task-cap >/dev/null 2>"$TMP/stderr" || rc=$?

  printf '%s\n%s\n%s\n' "$rc" "$TMP/herdr.log" "$REPO" > "$TMP/.result"
  cat "$TMP/.result"
}

# Case 1: probe passes -> brief must be delivered, task recorded as dispatched.
read -r RC LOG REPO <<< "$(run_case PASS | tr '\n' ' ')"
RC=$(printf '%s' "$RC")
[ "$RC" = 0 ] || { echo "spawn should succeed when probe passes (rc=$RC)" >&2; exit 1; }
grep -c ' agent prompt ' "$LOG" | grep -qx 2 || { echo "expected exactly one probe prompt + one substantive prompt on PASS" >&2; cat "$LOG" >&2; exit 1; }
[ -f "$REPO/.harness-state/task-cap.meta" ] || { echo "task should be recorded as dispatched on PASS" >&2; exit 1; }
rm -rf "$(dirname "$LOG")"

# Case 2: probe fails -> the substantive brief must never be sent, and the task must not be recorded.
read -r RC LOG REPO <<< "$(run_case 'FAIL figma' | tr '\n' ' ')"
RC=$(printf '%s' "$RC")
[ "$RC" != 0 ] || { echo "spawn should fail when probe fails" >&2; exit 1; }
grep -q ' agent prompt ' "$LOG" || { echo "the probe prompt itself should still have been sent" >&2; exit 1; }
if grep -c ' agent prompt ' "$LOG" | grep -qx 2; then
  echo "a second 'agent prompt' call means the substantive brief may have been delivered after a failed probe" >&2
  exit 1
fi
[ -f "$REPO/.harness-state/task-cap.meta" ] && { echo "task must NOT be recorded as dispatched when the probe fails" >&2; exit 1; }
rm -rf "$(dirname "$LOG")"

echo 'capability-aware dispatch tests: ok'

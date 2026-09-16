#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/plan" "$REPO/projects/demo/plan" "$REPO/.harness-state" "$FAKEBIN"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" \
  "$ROOT/scripts/quota-resume-lib.sh" "$ROOT/scripts/agent-wait.sh" \
  "$ROOT/scripts/codex-completion-lib.sh" "$ROOT/scripts/codex-completion-watch.sh" "$REPO/scripts/"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}" "${FAKE_RECIPIENT_ENGINE:?}" "${FAKE_RECIPIENT_STATUS:?}" \
  "${FAKE_RECIPIENT_ID:?}" "${FAKE_TASK_META:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"

case " $* " in
  *" agent get source-agent"*)
    printf '%s\n' '{"result":{"agent":{"agent":"claude","agent_status":"idle","pane_id":"w2:p2"}}}'
    ;;
  *" agent get w9:p9 "*)
    engine=$(cat "$FAKE_RECIPIENT_ENGINE")
    status=$(cat "$FAKE_RECIPIENT_STATUS")
    session_id=$(cat "$FAKE_RECIPIENT_ID")
    jq -nc --arg engine "$engine" --arg status "$status" --arg sessionId "$session_id" \
      '{result:{agent:{agent:$engine,agent_status:$status,pane_id:"w9:p9",agent_session:{agent:$engine,kind:"id",source:("herdr:"+$engine),value:$sessionId}}}}'
    ;;
  *" agent wait source-agent "*)
    [ "${FAKE_SOURCE_WAIT_FAIL:-0}" != 1 ] || exit 1
    case "${FAKE_AFTER_SOURCE:-none}" in
      replace) printf '%s\n' replacement-session > "$FAKE_RECIPIENT_ID" ;;
      blocked) printf '%s\n' blocked > "$FAKE_RECIPIENT_STATUS" ;;
      busy) printf '%s\n' working > "$FAKE_RECIPIENT_STATUS" ;;
      task-switch) sed -i.bak 's/^generation=.*/generation=2/' "$FAKE_TASK_META" ;;
      task-missing) rm "$FAKE_TASK_META" ;;
      quota)
        sed -i.bak 's/^generation=.*/generation=2/;s/^agent_name=.*/agent_name=source-agent-2/' "$FAKE_TASK_META"
        mkdir -p "$FAKE_HISTORY"
        task=$(sed -n 's/^task=//p' "$FAKE_TASK_META")
        jq -nc --arg task "$task" \
          '{schema:"harness-agent-switch.v1",task:$task,from:"claude",to:"claude",oldAgent:"source-agent",newAgent:"source-agent-2",note:"Provider quota reset. Resume automatically.",switchedAt:"2099-01-01T00:00:00Z"}' >> "$FAKE_HISTORY/$task.jsonl"
        ;;
    esac
    printf '%s\n' '{"result":{}}'
    ;;
  *" agent wait w9:p9 "*)
    [ "${FAKE_RECIPIENT_WAIT_FAIL:-0}" != 1 ] || exit 1
    printf '%s\n' idle > "$FAKE_RECIPIENT_STATUS"
    printf '%s\n' '{"result":{}}'
    ;;
  *" agent prompt w9:p9 "*)
    [ "${FAKE_PROMPT_FAIL:-0}" != 1 ] || exit 1
    printf '%s\n' '{"result":{}}'
    ;;
  *" agent read source-agent "*) printf '%s\n' '{"result":{}}' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

cd "$REPO"
git init -q
git config user.email test@example.com
git config user.name Test
git add scripts
git commit -qm initial

export PATH="$FAKEBIN:$PATH"
export HARNESS_HERDR_SESSION=test-harness
export FAKE_HERDR_LOG="$TMP/herdr.log"
export FAKE_RECIPIENT_ENGINE="$TMP/recipient-engine"
export FAKE_RECIPIENT_STATUS="$TMP/recipient-status"
export FAKE_RECIPIENT_ID="$TMP/recipient-id"
export FAKE_TASK_META="$REPO/.harness-state/unused.meta"
export FAKE_HISTORY="$REPO/.harness-state/agent-history"

reset_fake() {
  : > "$FAKE_HERDR_LOG"
  printf '%s\n' codex > "$FAKE_RECIPIENT_ENGINE"
  printf '%s\n' idle > "$FAKE_RECIPIENT_STATUS"
  printf '%s\n' codex-session-1 > "$FAKE_RECIPIENT_ID"
  unset FAKE_SOURCE_WAIT_FAIL FAKE_RECIPIENT_WAIT_FAIL FAKE_AFTER_SOURCE FAKE_PROMPT_FAIL
}

write_task() {
  local id=$1 generation=${2:-1} location=${3:-root} card worktree
  worktree="$TMP/worktrees/$id"
  mkdir -p "$worktree/reports"
  if [ "$location" = nested ]; then card="$REPO/projects/demo/plan/$id-card.md"; else card="$REPO/plan/$id-card.md"; fi
  printf '# %s\n**Status:** in-progress · **Owner:** shell-engineer\n' "$id" > "$card"
  cat > "$REPO/.harness-state/$id.meta" <<EOF
schema=harness-herdr-task.v1
task=$id
card=${card#"$REPO"/}
project=$([ "$location" = nested ] && printf demo || printf jarvis)
agent=shell-engineer
agent_name=source-agent
engine=claude
generation=$generation
session=source-session
pane=w2:p2
worktree=$worktree
stopped=0
EOF
  export FAKE_TASK_META="$REPO/.harness-state/$id.meta"
}

prompt_count() {
  awk '/ agent prompt w9:p9 / { count++ } END { print count+0 }' "$FAKE_HERDR_LOG"
}

assert_state() {
  local id=$1 expected=$2
  actual=$(sed -n 's/^status=//p' "$REPO/.harness-state/codex-completion/$id.meta")
  [ "$actual" = "$expected" ] || { echo "expected $id state $expected, got $actual" >&2; exit 1; }
}

# Normal delivery supports a frozen legacy id in a nested project and records exactly one prompt.
reset_fake
write_task T1 1 nested
scripts/codex-completion-watch.sh start T1 --session default --pane w9:p9
assert_state T1 delivered
[ "$(prompt_count)" = 1 ] || { echo 'normal delivery did not send exactly one prompt' >&2; exit 1; }
grep -q -- '--session source-session agent wait source-agent' "$FAKE_HERDR_LOG"
grep -q "$REPO/.harness-state/T1.meta" "$FAKE_HERDR_LOG"
grep -q "$TMP/worktrees/T1/reports/T1-shell-engineer.md" "$FAKE_HERDR_LOG"
scripts/codex-completion-watch.sh status T1 | jq -e '.status == "delivered" and .recipient.session == "default"' >/dev/null
if scripts/codex-completion-watch.sh start T1 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'duplicate registration unexpectedly succeeded' >&2
  exit 1
fi
[ "$(prompt_count)" = 1 ] || { echo 'duplicate registration sent a second prompt' >&2; exit 1; }

# A timestamp id in the reserved root project follows the same path.
reset_fake
write_task 260916-1454-002 1 root
scripts/codex-completion-watch.sh start 260916-1454-002 --session default --pane w9:p9
assert_state 260916-1454-002 delivered
[ "$(prompt_count)" = 1 ] || { echo 'timestamp/root delivery did not send exactly one prompt' >&2; exit 1; }

# Recipient replacement after registration is stale and must never receive the completion prompt.
reset_fake
write_task T2
export FAKE_AFTER_SOURCE=replace
if scripts/codex-completion-watch.sh start T2 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'recipient replacement unexpectedly delivered' >&2
  exit 1
fi
assert_state T2 failed
[ "$(prompt_count)" = 0 ] || { echo 'recipient replacement received a prompt' >&2; exit 1; }

# A non-Codex recipient is rejected before a claim is created.
reset_fake
write_task T3
printf '%s\n' claude > "$FAKE_RECIPIENT_ENGINE"
if scripts/codex-completion-watch.sh start T3 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'wrong-engine recipient unexpectedly registered' >&2
  exit 1
fi
[ ! -e "$REPO/.harness-state/codex-completion/T3.meta" ]
[ "$(prompt_count)" = 0 ] || { echo 'wrong-engine recipient received a prompt' >&2; exit 1; }

# A blocked recipient stays durably waiting; no input is injected into its approval/question UI.
reset_fake
write_task T4
export FAKE_AFTER_SOURCE=blocked
scripts/codex-completion-watch.sh start T4 --session default --pane w9:p9
assert_state T4 waiting
[ "$(prompt_count)" = 0 ] || { echo 'blocked recipient received a prompt' >&2; exit 1; }
unset FAKE_AFTER_SOURCE
printf '%s\n' idle > "$FAKE_RECIPIENT_STATUS"
scripts/codex-completion-watch.sh reconcile T4 --retry >/dev/null
assert_state T4 delivered
[ "$(prompt_count)" = 1 ] || { echo 'explicit blocked-recipient retry did not deliver exactly once' >&2; exit 1; }

# A busy recipient is waited on outside the model. Failure to settle is diagnosable and sends none.
reset_fake
write_task T5
export FAKE_AFTER_SOURCE=busy
export FAKE_RECIPIENT_WAIT_FAIL=1
if scripts/codex-completion-watch.sh start T5 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'failed recipient wait unexpectedly delivered' >&2
  exit 1
fi
assert_state T5 failed
[ "$(prompt_count)" = 0 ] || { echo 'busy recipient received a prompt after wait failure' >&2; exit 1; }

# A busy recipient that settles is revalidated, then receives one prompt.
reset_fake
write_task T6
export FAKE_AFTER_SOURCE=busy
scripts/codex-completion-watch.sh start T6 --session default --pane w9:p9
assert_state T6 delivered
[ "$(prompt_count)" = 1 ] || { echo 'settled busy recipient did not receive exactly one prompt' >&2; exit 1; }

# Switching the source task generation while waiting invalidates the watcher claim.
reset_fake
write_task T7
export FAKE_AFTER_SOURCE=task-switch
if scripts/codex-completion-watch.sh start T7 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'stale task generation unexpectedly delivered' >&2
  exit 1
fi
assert_state T7 failed
[ "$(prompt_count)" = 0 ] || { echo 'stale task generation sent a prompt' >&2; exit 1; }
scripts/codex-completion-watch.sh reconcile T7 --supersede | jq -e '.status == "superseded"' >/dev/null
[ ! -e "$REPO/.harness-state/codex-completion/T7.meta" ]
find "$REPO/.harness-state/codex-completion/archive" -type f -name 'T7.g1.a1.*.meta' | grep -q .
reset_fake
write_task T7 2
scripts/codex-completion-watch.sh start T7 --session default --pane w9:p9
assert_state T7 delivered
[ "$(prompt_count)" = 1 ] || { echo 'superseded generation did not permit one fresh delivery' >&2; exit 1; }

# The same generation advance is accepted only when agent-wait's quota relaunch ledger proves it.
reset_fake
write_task T7Q
export FAKE_AFTER_SOURCE=quota
scripts/codex-completion-watch.sh start T7Q --session named-harness --pane w9:p9
assert_state T7Q delivered
[ "$(prompt_count)" = 1 ] || { echo 'recorded quota recovery did not deliver exactly once' >&2; exit 1; }
grep -q -- '--session named-harness agent prompt w9:p9' "$FAKE_HERDR_LOG"
grep -q '^source_generation=2$' "$REPO/.harness-state/codex-completion/T7Q.meta"
grep -q '^source_agent_name=source-agent-2$' "$REPO/.harness-state/codex-completion/T7Q.meta"

# Missing task metadata at registration and after waiting both fail without delivery.
reset_fake
if scripts/codex-completion-watch.sh start missing-task --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'missing task unexpectedly registered' >&2
  exit 1
fi
[ "$(prompt_count)" = 0 ] || { echo 'missing task sent a prompt' >&2; exit 1; }

reset_fake
write_task T8
export FAKE_AFTER_SOURCE=task-missing
if scripts/codex-completion-watch.sh start T8 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'task removed during wait unexpectedly delivered' >&2
  exit 1
fi
assert_state T8 failed
[ "$(prompt_count)" = 0 ] || { echo 'task removed during wait sent a prompt' >&2; exit 1; }

# A source wait failure remains retryable through durable failed state and sends nothing.
reset_fake
write_task T9
export FAKE_SOURCE_WAIT_FAIL=1
if scripts/codex-completion-watch.sh start T9 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'source wait failure unexpectedly delivered' >&2
  exit 1
fi
assert_state T9 failed
[ "$(prompt_count)" = 0 ] || { echo 'source wait failure sent a prompt' >&2; exit 1; }

# A failed prompt call is ambiguous: never mark delivered and never resend automatically.
reset_fake
write_task T10
export FAKE_PROMPT_FAIL=1
if scripts/codex-completion-watch.sh start T10 --session default --pane w9:p9 >/dev/null 2>&1; then
  echo 'ambiguous prompt failure unexpectedly succeeded' >&2
  exit 1
fi
assert_state T10 uncertain
[ "$(prompt_count)" = 1 ] || { echo 'ambiguous delivery should record one attempted prompt' >&2; exit 1; }
scripts/codex-completion-watch.sh reconcile T10 >/dev/null
[ "$(prompt_count)" = 1 ] || { echo 'reconcile automatically resent an ambiguous prompt' >&2; exit 1; }
scripts/codex-completion-watch.sh reconcile T10 --delivered >/dev/null
assert_state T10 delivered
[ "$(prompt_count)" = 1 ] || { echo 'manual delivered reconciliation sent another prompt' >&2; exit 1; }

# Fleet mutation remains forbidden from a linked Jarvis task worktree.
LINKED="$TMP/linked"
git worktree add -q -b harness/guard-test "$LINKED" HEAD
if HARNESS_STATE_DIR="$TMP/linked-state" "$LINKED/scripts/codex-completion-watch.sh" start T11 --session default --pane w9:p9 >/dev/null 2>"$TMP/guard.err"; then
  echo 'watcher registration unexpectedly mutated from a linked worktree' >&2
  exit 1
fi
grep -q 'linked Jarvis task worktree' "$TMP/guard.err"
[ ! -e "$TMP/linked-state/codex-completion/T11.meta" ]

echo 'codex completion watcher tests: ok'

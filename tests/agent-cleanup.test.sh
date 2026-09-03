#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/state" "$TMP/bin"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/harness-event-lib.sh" \
  "$ROOT/scripts/inbox.sh" "$ROOT/scripts/decisions.sh" "$ROOT/scripts/events-poll.sh" \
  "$ROOT/scripts/quota-resume-lib.sh" "$ROOT/scripts/quota-resume-poll.sh" "$ROOT/scripts/agent-cleanup.sh" \
  "$TMP/scripts/"
chmod +x "$TMP/scripts/quota-resume-poll.sh" "$TMP/scripts/agent-cleanup.sh"
cat > "$TMP/scripts/fleet-snapshot.sh" <<'FAKE'
#!/usr/bin/env bash
cat "${FAKE_SNAPSHOT:?}"
FAKE
chmod +x "$TMP/scripts/fleet-snapshot.sh"

cat > "$TMP/bin/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
args=" $* "
case "$args" in
  *" tab close "*)
    if [ "${FAKE_TAB_CLOSE_FAIL:-0}" = 1 ]; then exit 1; fi
    printf '%s\n' '{"result":{"ok":true}}'
    ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$TMP/bin/herdr"

export PATH="$TMP/bin:$PATH"
export HARNESS_STATE_DIR="$TMP/state"
export HARNESS_HERDR_SESSION="test-harness"
export FAKE_HERDR_LOG="$TMP/herdr.log"
: > "$FAKE_HERDR_LOG"

write_meta() {
  local task=$1 agent_name=$2 tab=$3 generation=$4
  cat > "$TMP/state/$task.meta" <<EOF
schema=harness-herdr-task.v1
task=$task
agent=engineer
agent_name=$agent_name
engine=claude
generation=$generation
session=test-harness
workspace=w1
tab=$tab
pane=p1
worktree=/nonexistent
branch=harness/$task
stopped=0
EOF
}

tab_close_count() { grep -c " tab close " "$FAKE_HERDR_LOG" || true; }

# --- scenario 1: ordering, ack gating, exact target, close-failure retry, idempotence -----------
write_meta t1 agent_t1 tab1 1
cat > "$TMP/snap-1a.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"t1","runtime":{"observed":"working"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}}
]}
JSON
FAKE_SNAPSHOT="$TMP/snap-1a.json" "$TMP/scripts/events-poll.sh" >/dev/null
cat > "$TMP/snap-1b.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"t1","runtime":{"observed":"done"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}}
]}
JSON
FAKE_SNAPSHOT="$TMP/snap-1b.json" "$TMP/scripts/events-poll.sh" >/dev/null
EVENT_JSON=$("$TMP/scripts/inbox.sh" list --json | jq -c '.[] | select(.task=="t1" and .type=="agent-done")')
EVENT1=$(printf '%s' "$EVENT_JSON" | jq -r '.id')
printf '%s' "$EVENT_JSON" | jq -e '.identity.tab == "tab1" and .identity.agentName == "agent_t1" and .identity.generation == 1' >/dev/null

# no close before acknowledgement (persist-before-close ordering)
if "$TMP/scripts/agent-cleanup.sh" "$EVENT1" >/dev/null 2>&1; then
  echo 'cleanup before acknowledgement unexpectedly succeeded' >&2; exit 1
fi
test "$(tab_close_count)" = 0
grep -qx 'stopped=0' "$TMP/state/t1.meta"

"$TMP/scripts/inbox.sh" acknowledge "$EVENT1" >/dev/null

# close failure: leaves meta/ack intact, non-zero exit, retryable
if FAKE_TAB_CLOSE_FAIL=1 "$TMP/scripts/agent-cleanup.sh" "$EVENT1" >/dev/null 2>&1; then
  echo 'cleanup unexpectedly succeeded despite forced tab-close failure' >&2; exit 1
fi
test "$(tab_close_count)" = 1
grep -qx 'stopped=0' "$TMP/state/t1.meta"
"$TMP/scripts/inbox.sh" list --json | jq -e '[.[] | select(.task=="t1")] | length == 0' >/dev/null
grep -q "$EVENT1" "$TMP/state/event-acks.jsonl"

# successful retry: exact tab targeted, meta marked stopped
"$TMP/scripts/agent-cleanup.sh" "$EVENT1" | grep -q 'closed settled tab tab1'
grep -q ' tab close tab1' "$FAKE_HERDR_LOG"
grep -qx 'stopped=1' "$TMP/state/t1.meta"
test "$(tab_close_count)" = 2

# double cleanup: idempotent no-op, no further tab close attempts
"$TMP/scripts/agent-cleanup.sh" "$EVENT1" | grep -q 'already stopped'
test "$(tab_close_count)" = 2

# --- scenario 2: generation/fingerprint mismatch — newer replacement is never touched -----------
write_meta t2 agent_t2 tabA 1
cat > "$TMP/snap-2a.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"t2","runtime":{"observed":"working"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}}
]}
JSON
FAKE_SNAPSHOT="$TMP/snap-2a.json" "$TMP/scripts/events-poll.sh" >/dev/null
cat > "$TMP/snap-2b.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"t2","runtime":{"observed":"done"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}}
]}
JSON
FAKE_SNAPSHOT="$TMP/snap-2b.json" "$TMP/scripts/events-poll.sh" >/dev/null
EVENT2=$("$TMP/scripts/inbox.sh" list --json | jq -r '.[] | select(.task=="t2" and .type=="agent-done") | .id')
"$TMP/scripts/inbox.sh" acknowledge "$EVENT2" >/dev/null
# simulate a switch/review handoff that happened after done but before cleanup ran
write_meta t2 agent_t2b tabB 2
BEFORE=$(tab_close_count)
"$TMP/scripts/agent-cleanup.sh" "$EVENT2" | grep -q 'metadata moved past the settled generation'
test "$(tab_close_count)" = "$BEFORE"
grep -qx 'stopped=0' "$TMP/state/t2.meta"
grep -qx 'tab=tabB' "$TMP/state/t2.meta"

# --- scenario 3: blocked never auto-closes ------------------------------------------------------
write_meta t3 agent_t3 tabC 1
cat > "$TMP/snap-3a.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"t3","runtime":{"observed":"working"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}}
]}
JSON
FAKE_SNAPSHOT="$TMP/snap-3a.json" "$TMP/scripts/events-poll.sh" >/dev/null
cat > "$TMP/snap-3b.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"t3","runtime":{"observed":"blocked"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}}
]}
JSON
FAKE_SNAPSHOT="$TMP/snap-3b.json" "$TMP/scripts/events-poll.sh" >/dev/null
EVENT3=$("$TMP/scripts/inbox.sh" list --json | jq -r '.[] | select(.task=="t3" and .type=="agent-blocked") | .id')
"$TMP/scripts/inbox.sh" acknowledge "$EVENT3" >/dev/null
BEFORE=$(tab_close_count)
if "$TMP/scripts/agent-cleanup.sh" "$EVENT3" >/dev/null 2>&1; then
  echo 'cleanup on a blocked event unexpectedly succeeded' >&2; exit 1
fi
test "$(tab_close_count)" = "$BEFORE"
grep -qx 'stopped=0' "$TMP/state/t3.meta"

echo 'agent cleanup tests: ok'

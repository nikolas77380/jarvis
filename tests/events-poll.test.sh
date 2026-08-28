#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/state/clean-slate" "$TMP/run"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/harness-event-lib.sh" "$ROOT/scripts/inbox.sh" "$ROOT/scripts/decisions.sh" "$ROOT/scripts/events-poll.sh" "$TMP/scripts/"
cat > "$TMP/scripts/fleet-snapshot.sh" <<'FAKE'
#!/usr/bin/env bash
cat "${FAKE_SNAPSHOT:?}"
FAKE
chmod +x "$TMP/scripts/fleet-snapshot.sh"
cat > "$TMP/snapshot-1.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"a","runtime":{"observed":"working"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}},
 {"task":"b","runtime":{"observed":"blocked"},"worktree":{"head":"h2"},"cleanSlate":{"state":"none"}},
 {"task":"c","runtime":{"observed":"idle"},"worktree":{"head":"h3"},"cleanSlate":{"state":"awaiting-response"}}
]}
JSON
cat > "$TMP/state/clean-slate/c.meta" <<EOF
schema=harness-clean-slate.v1
task=c
state=awaiting-response
round=1
run_dir=$TMP/run
EOF
cat > "$TMP/run/review-1.json" <<'JSON'
{"outcome":"findings","findings":[{"id":"R7","class":"needs-decision","message":"Choose compatibility behavior"}]}
JSON
export HARNESS_STATE_DIR="$TMP/state"
FAKE_SNAPSHOT="$TMP/snapshot-1.json" "$TMP/scripts/events-poll.sh" >/dev/null
test "$("$TMP/scripts/inbox.sh" list --json | jq length)" = 2
DECISIONS_JSON=$("$TMP/scripts/decisions.sh" list --json)
printf '%s\n' "$DECISIONS_JSON" | jq -e 'length == 1 and .[0].key == "c-R7"' >/dev/null
FAKE_SNAPSHOT="$TMP/snapshot-1.json" "$TMP/scripts/events-poll.sh" >/dev/null
test "$(wc -l < "$TMP/state/events.jsonl" | tr -d ' ')" = 2

cat > "$TMP/snapshot-2.json" <<'JSON'
{"schema":"harness-fleet-snapshot.v1","tasks":[
 {"task":"a","runtime":{"observed":"done"},"worktree":{"head":"h1"},"cleanSlate":{"state":"none"}},
 {"task":"b","runtime":{"observed":"missing"},"worktree":{"head":"h2"},"cleanSlate":{"state":"none"}},
 {"task":"c","runtime":{"observed":"idle"},"worktree":{"head":"h3"},"cleanSlate":{"state":"ready"}}
]}
JSON
FAKE_SNAPSHOT="$TMP/snapshot-2.json" "$TMP/scripts/events-poll.sh" >/dev/null
test "$(wc -l < "$TMP/state/events.jsonl" | tr -d ' ')" = 5
"$TMP/scripts/inbox.sh" list --json | jq -e '[.[].type] | index("agent-done") and index("agent-missing") and index("ci-ready")' >/dev/null

echo 'events poll tests: ok'

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/state"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/harness-event-lib.sh" "$ROOT/scripts/inbox.sh" "$ROOT/scripts/decisions.sh" "$TMP/scripts/"
export HARNESS_STATE_DIR="$TMP/state"

ID1=$("$TMP/scripts/inbox.sh" emit task-a agent-done head-1 'Agent completed')
ID2=$("$TMP/scripts/inbox.sh" emit task-a agent-done head-1 'Agent completed')
test "$ID1" = "$ID2"
test "$(wc -l < "$TMP/state/events.jsonl" | tr -d ' ')" = 1
"$TMP/scripts/inbox.sh" list --json | jq -e 'length == 1 and .[0].type == "agent-done"' >/dev/null
"$TMP/scripts/inbox.sh" acknowledge "$ID1" >/dev/null
"$TMP/scripts/inbox.sh" acknowledge "$ID1" >/dev/null
test "$("$TMP/scripts/inbox.sh" list --json | jq length)" = 0
test "$(wc -l < "$TMP/state/event-acks.jsonl" | tr -d ' ')" = 1

"$TMP/scripts/decisions.sh" open task-a --key auth-expiry --question 'Reject or refresh?' >/dev/null
"$TMP/scripts/decisions.sh" open task-a --key auth-expiry --question 'Reject or refresh?' >/dev/null
test "$(wc -l < "$TMP/state/decisions.jsonl" | tr -d ' ')" = 1
"$TMP/scripts/decisions.sh" list --json | jq -e 'length == 1 and .[0].key == "auth-expiry"' >/dev/null
"$TMP/scripts/decisions.sh" resolve auth-expiry --answer 'Refresh once' >/dev/null
test "$("$TMP/scripts/decisions.sh" list --json | jq length)" = 0

echo 'inbox and decisions tests: ok'

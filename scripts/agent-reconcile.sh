#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
ID=${1:-}; MODE=${2:-}
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || { [ -n "$MODE" ] && [ "$MODE" != --repair ]; }; then
  die 'usage: agent-reconcile.sh <task-id> [--repair]'
fi
OBS=$("$HARNESS_ROOT/scripts/harness-observe.sh" "$ID")
if [ "$MODE" = --repair ] && printf '%s' "$OBS" | jq -e '.issues|index("runtime-agent-missing")' >/dev/null; then
  state_lock_acquire "$ID"
  META=$(require_meta "$ID")
  TMP=$(mktemp "$HARNESS_STATE/.reconcile.XXXXXX")
  sed 's/^stopped=.*/stopped=1/' "$META" > "$TMP"
  printf 'reconciled_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$TMP"
  chmod 600 "$TMP"; mv "$TMP" "$META"
  OBS=$("$HARNESS_ROOT/scripts/harness-observe.sh" "$ID")
fi
printf '%s\n' "$OBS"

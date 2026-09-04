#!/usr/bin/env bash
# Stop the exact Herdr tab owned by a task; preserve its worktree and branch.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$HARNESS_ROOT/scripts/harness-state-lib.sh"
ID=${1:-}
[ -n "$ID" ] || die "usage: agent-stop.sh <task-id>"
valid_task_id "$ID" || die "invalid task id: $ID"
state_lock_acquire "$ID"
require_tools
META=$(require_meta "$ID")
[ "$(meta_get "$META" stopped)" != 1 ] || { echo "already stopped: $ID"; exit 0; }
close_recorded_tab "$ID" "$META"
printf 'stopped: %s · worktree preserved: %s\n' "$ID" "$(meta_get "$META" worktree)"

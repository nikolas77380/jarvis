#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"
export HARNESS_STATE_DIR="$TMP/state"
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$ROOT/scripts/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$ROOT/scripts/harness-state-lib.sh"

state_lock_acquire task-a
test -d "$TMP/state/locks/task-a.lock"
if (state_lock_acquire task-a) >/dev/null 2>&1; then
  echo 'live lock unexpectedly acquired' >&2
  exit 1
fi
state_lock_release
test ! -e "$TMP/state/locks/task-a.lock"

mkdir -p "$TMP/state/locks/task-stale.lock"
printf 'pid=999999\nidentity=gone\n' > "$TMP/state/locks/task-stale.lock/owner.meta"
state_lock_acquire task-stale
grep -qx "pid=$$" "$TMP/state/locks/task-stale.lock/owner.meta"
state_lock_release

echo 'state lock tests: ok'

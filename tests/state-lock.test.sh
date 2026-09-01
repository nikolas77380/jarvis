#!/usr/bin/env bash
# state_lock_acquire mechanics, exercised against an isolated fixture repo — never against the
# ambient checkout this test happens to run from. Sourcing herdr-runtime-lib.sh against a repo whose
# own working copy is itself a linked Jarvis worktree (as this test file's own checkout may well be,
# when running under a task worktree) would otherwise make every state_lock_acquire call here trip
# the require_fleet_mutation_allowed guard added for the round-2 fix — a false failure of this test,
# not of the guard. The isolated fixture keeps this test about lock mechanics only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/scripts"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$REPO/scripts/"
cd "$REPO"
git init -q
git config user.email test@example.com
git config user.name Test
git add scripts
git commit -qm initial

mkdir -p "$TMP/state"
export HARNESS_STATE_DIR="$TMP/state"
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$REPO/scripts/herdr-runtime-lib.sh"
# shellcheck source=scripts/harness-state-lib.sh
. "$REPO/scripts/harness-state-lib.sh"

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

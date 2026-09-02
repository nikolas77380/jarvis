# Sourced from an isolated copy, never straight from $ROOT: this test file's own checkout may
# itself be a linked Jarvis task worktree (as it is under a task worktree), and sourcing
# herdr-runtime-lib.sh straight from $ROOT would then trip the require_fleet_mutation_allowed guard
# on quota_meta_write below - a false failure of this test, not of the guard. See the same note in
# tests/state-lock.test.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/quota-resume-lib.sh" "$TMP/scripts/"
export HARNESS_STATE_DIR="$TMP/state"
. "$TMP/scripts/herdr-runtime-lib.sh"
. "$TMP/scripts/quota-resume-lib.sh"

printf '%s\n' "You've hit your monthly spend limit; your session limit resets 2:10am (Europe/Sofia)" | quota_message_matches
if printf '%s\n' 'ordinary task completed' | quota_message_matches; then
  echo 'ordinary completion was classified as quota' >&2
  exit 1
fi
EPOCH=$(quota_resume_epoch 'limit resets 2:10am (Europe/Sofia)' 0)
case "$EPOCH" in ''|*[!0-9]*) echo 'clock reset did not produce an epoch' >&2; exit 1 ;; esac
NOW=$(date +%s)
CLOCK=$(TZ=Europe/Sofia date '+%I:%M%p')
test "$(quota_resume_epoch "limit resets $CLOCK (Europe/Sofia)" "$NOW")" = "$NOW"
ISO_EPOCH=$(quota_resume_epoch 'quota reset 2030-01-02T03:04:05Z' 0)
test "$ISO_EPOCH" = 1893553445
META=$(quota_meta_write task-1 task claude "$ISO_EPOCH" $'monthly spend limit\nresets soon')
grep -qx 'blocked_reason=quota' "$META"
grep -qx "resume_at=$ISO_EPOCH" "$META"
grep -qx 'excerpt=monthly spend limit resets soon' "$META"

quota_meta_remove task-1
[ ! -e "$META" ] || { echo 'quota_meta_remove did not delete the quota file' >&2; exit 1; }

# Both mutators go through the same guard as every other fleet-mutating choke point.
export IS_JARVIS_LINKED_WORKTREE=true JARVIS_LINKED_WORKTREE_PATH=/fake/worktree
if (quota_meta_write task-2 task claude "$ISO_EPOCH" excerpt) >/dev/null 2>"$TMP/err"; then
  echo 'quota_meta_write unexpectedly succeeded while flagged as a linked Jarvis task worktree' >&2
  exit 1
fi
grep -q 'linked Jarvis task worktree' "$TMP/err" \
  || { echo "quota_meta_write did not refuse with the guard message: $(cat "$TMP/err")" >&2; exit 1; }
[ ! -e "$HARNESS_STATE/quota/task-2.meta" ] \
  || { echo 'quota_meta_write created a file despite refusing' >&2; exit 1; }

if (quota_meta_remove task-1) >/dev/null 2>"$TMP/err"; then
  echo 'quota_meta_remove unexpectedly succeeded while flagged as a linked Jarvis task worktree' >&2
  exit 1
fi
grep -q 'linked Jarvis task worktree' "$TMP/err" \
  || { echo "quota_meta_remove did not refuse with the guard message: $(cat "$TMP/err")" >&2; exit 1; }
export IS_JARVIS_LINKED_WORKTREE=false JARVIS_LINKED_WORKTREE_PATH=

printf 'quota-resume tests: ok\n'

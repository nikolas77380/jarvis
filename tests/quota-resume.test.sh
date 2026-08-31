#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HARNESS_STATE_DIR="$TMP/state"
. "$ROOT/scripts/herdr-runtime-lib.sh"
. "$ROOT/scripts/quota-resume-lib.sh"

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
printf 'quota-resume tests: ok\n'

#!/usr/bin/env bash
# Foreground supervisor for quota recovery. Run under the harness's tracked process manager.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTERVAL=${QUOTA_RESUME_INTERVAL_SECONDS:-30}
case "$INTERVAL" in ''|*[!0-9]*|0) echo 'QUOTA_RESUME_INTERVAL_SECONDS must be a positive integer' >&2; exit 2 ;; esac

while :; do
  "$ROOT/scripts/quota-resume-poll.sh"
  sleep "$INTERVAL"
done

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMAT=${1:-}
if [ "$#" -gt 1 ] || { [ -n "$FORMAT" ] && [ "$FORMAT" != --json ]; }; then
  echo 'usage: harness-doctor.sh [--json]' >&2; exit 2
fi
SNAPSHOT=$("$ROOT/scripts/fleet-snapshot.sh" --json)
REPORT=$(printf '%s' "$SNAPSHOT" | jq '{schema:"harness-doctor.v1",healthy:([.tasks[].issues[]]|length==0),issueCount:([.tasks[].issues[]]|length),tasks:[.tasks[]|select(.consistent|not)|{task,issues}]}')
if [ "$FORMAT" = --json ]; then printf '%s\n' "$REPORT"; else printf '%s\n' "$REPORT" | jq -r 'if .healthy then "doctor: healthy" else .tasks[] | "\(.task): \(.issues|join(", "))" end'; fi
printf '%s' "$REPORT" | jq -e '.healthy' >/dev/null

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
require_tools
printf '%-32s %-16s %-20s %-10s %s\n' TASK PROJECT AGENT STATE WORKTREE
found=0
for META in "$HARNESS_STATE"/*.meta; do
  [ -f "$META" ] || continue
  case "$META" in */herdr-workspace.meta) continue ;; esac
  found=1
  ID=$(meta_get "$META" task)
  PROJECT=$(meta_get "$META" project)
  AGENT=$(meta_get "$META" agent)
  if [ "$(meta_get "$META" stopped)" = 1 ]; then
    STATE=stopped
  else
    STATE=$(agent_status "$(meta_get "$META" agent_name)" "$(meta_get "$META" session)")
  fi
  printf '%-32s %-16s %-20s %-10s %s\n' "$ID" "$PROJECT" "$AGENT" "$STATE" "$(meta_get "$META" worktree)"
done
[ "$found" = 1 ] || echo '(no recorded agents)'

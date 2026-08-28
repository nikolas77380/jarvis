#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMAT=${1:-}
if [ "$#" -gt 1 ] || { [ -n "$FORMAT" ] && [ "$FORMAT" != --json ]; }; then
  echo 'usage: fleet-snapshot.sh [--json]' >&2; exit 2
fi
TMP=$(mktemp)
IDS=$(mktemp)
trap 'rm -f "$TMP" "$IDS"' EXIT
for META in "${HARNESS_STATE_DIR:-$ROOT/.harness-state}"/*.meta; do
  [ -f "$META" ] || continue
  case "$META" in */herdr-workspace.meta) continue ;; esac
  ID=$(sed -n 's/^task=//p' "$META" | tail -1)
  [ -n "$ID" ] && printf '%s\n' "$ID" >> "$IDS"
done
for CARD in "$ROOT"/plan/*.md; do
  [ -f "$CARD" ] || continue
  case "$CARD" in */INDEX.md|*/TEMPLATE.md) continue ;; esac
  basename "$CARD" .md >> "$IDS"
done
sort -u "$IDS" | while IFS= read -r ID; do
  HARNESS_STATE_DIR="${HARNESS_STATE_DIR:-$ROOT/.harness-state}" "$ROOT/scripts/harness-observe.sh" "$ID" >> "$TMP"
done
JSON=$(jq -s '{schema:"harness-fleet-snapshot.v1",tasks:.}' "$TMP")
if [ "$FORMAT" = --json ]; then printf '%s\n' "$JSON"; else printf '%s\n' "$JSON" | jq -r '.tasks[] | [.task,.project,.runtime.observed,.worktree.clean,.cleanSlate.state,.nextAction] | @tsv'; fi

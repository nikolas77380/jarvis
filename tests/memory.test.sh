#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/harness"
mkdir -p "$REPO/scripts" "$REPO/memory/projects" "$REPO/memory/incidents"
cp "$ROOT/scripts/memory-context.sh" "$ROOT/scripts/memory-record.sh" "$ROOT/scripts/memory-promote.sh" "$REPO/scripts/"
printf '# Captain\n\n- Ask before merge.\n' > "$REPO/memory/captain.md"
printf '# Harness\n\n- Preserve branches.\n' > "$REPO/memory/harness.md"
printf '# Alpha\n\n- Uses main.\n' > "$REPO/memory/projects/alpha.md"
printf '# Beta\n\n- Uses trunk.\n' > "$REPO/memory/projects/beta.md"

CONTEXT=$("$REPO/scripts/memory-context.sh" --project alpha)
printf '%s' "$CONTEXT" | grep -q 'Ask before merge'
printf '%s' "$CONTEXT" | grep -q 'Preserve branches'
printf '%s' "$CONTEXT" | grep -q 'Uses main'
if printf '%s' "$CONTEXT" | grep -q 'Uses trunk'; then echo 'cross-project memory leaked' >&2; exit 1; fi

"$REPO/scripts/memory-record.sh" incident alpha flaky-check --summary 'The check fails after a stale cache.' >/dev/null
INCIDENT="$REPO/memory/incidents/alpha/flaky-check.md"
grep -q '^status: open$' "$INCIDENT"
"$REPO/scripts/memory-context.sh" --project alpha --include-incidents | grep -q 'stale cache'
"$REPO/scripts/memory-promote.sh" alpha/flaky-check --scope project --project alpha >/dev/null
grep -q '^status: promoted$' "$INCIDENT"
grep -q 'Source: memory/incidents/alpha/flaky-check.md' "$REPO/memory/projects/alpha.md"
if "$REPO/scripts/memory-promote.sh" alpha/flaky-check --scope project --project alpha >/dev/null 2>&1; then
  echo 'incident was promoted twice' >&2
  exit 1
fi

"$REPO/scripts/memory-context.sh" --project alpha --json | jq -e '.schema == "harness-memory-context.v1" and .project == "alpha" and (.sources|length)==3' >/dev/null
echo 'memory tests: ok'

#!/usr/bin/env bash
# Prepend an entry to OVERVIEW.md without reading the file into an agent's context.
#
# Why this exists: editing the file through a read-then-edit tool costs the whole file
# (~20k tokens) on EVERY append. This inserts after the "# Overview" heading instead, so an
# append costs nothing but the entry itself.
#
# Usage:
#   scripts/overview-append.sh "short title" <<'EOF'
#   Body lines. What happened and why it matters. Keep it to a short paragraph.
#   EOF
#
# Env: OVERVIEW_FILE overrides the target (default: OVERVIEW.md next to this script's repo root).

set -euo pipefail

ANCHOR="<!-- entries: new ones are inserted directly below this line -->"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${OVERVIEW_FILE:-$ROOT/OVERVIEW.md}"

MAX_ENTRIES=10
MAX_BYTES=61440   # 60 KB — the backstop; the entry count is the primary rule

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") \"short title\" < body" >&2
  exit 64
fi
title="$1"

if [ ! -f "$FILE" ]; then
  echo "error: $FILE does not exist" >&2
  exit 66
fi

# The anchor must appear exactly once, or an insert would silently no-op or duplicate.
anchor_count="$(grep -c "^${ANCHOR}\$" "$FILE" || true)"
if [ "$anchor_count" -ne 1 ]; then
  echo "error: found $anchor_count lines matching '^${ANCHOR}\$' in $FILE — expected exactly 1" >&2
  exit 65
fi

body="$(cat)"
if [ -z "${body//[[:space:]]/}" ]; then
  echo "error: empty body on stdin — an entry with no content is worse than no entry" >&2
  exit 64
fi

entry_file="$(mktemp)"
out_file="$(mktemp)"
trap 'rm -f "$entry_file" "$out_file"' EXIT

{
  printf '## %s — %s\n\n' "$(date -u '+%Y-%m-%d')" "$title"
  printf '%s\n' "$body"
} > "$entry_file"

awk -v ef="$entry_file" '
  { print }
  !inserted && $0 == "'"$ANCHOR"'" {
    print ""
    while ((getline line < ef) > 0) print line
    close(ef)
    inserted = 1
  }
' "$FILE" > "$out_file"

# Never move a truncated file over the only record of what happened.
if [ ! -s "$out_file" ]; then
  echo "error: produced an empty file — refusing to overwrite $FILE" >&2
  exit 70
fi
if ! grep -qF -- "$title" "$out_file"; then
  echo "error: entry not found in the result — refusing to overwrite $FILE" >&2
  exit 70
fi

mv "$out_file" "$FILE"
trap 'rm -f "$entry_file"' EXIT

entries="$(grep -c '^## ' "$FILE" || true)"
bytes="$(wc -c < "$FILE" | tr -d ' ')"
echo "appended to $FILE — $entries entries, $bytes bytes"

if [ "$entries" -gt "$MAX_ENTRIES" ] || [ "$bytes" -gt "$MAX_BYTES" ]; then
  echo "TRIM: move the oldest entries to docs/overview-archive/$(date -u '+%Y-%m').md" \
       "(limit: $MAX_ENTRIES entries, ${MAX_BYTES} bytes)" >&2
fi

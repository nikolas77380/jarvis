#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$#" -eq 5 ] && [ "$1" = incident ] && [ "$4" = --summary ] || { echo 'usage: memory-record.sh incident <project|global> <slug> --summary <text>' >&2; exit 2; }
PROJECT=$2; SLUG=$3; SUMMARY=$5
case "$PROJECT" in ''|*[!a-zA-Z0-9._-]*) echo "error: invalid project: $PROJECT" >&2; exit 1 ;; esac
case "$SLUG" in ''|*[!a-zA-Z0-9._-]*) echo "error: invalid incident slug: $SLUG" >&2; exit 1 ;; esac
[ -n "$SUMMARY" ] || { echo 'error: summary is empty' >&2; exit 1; }
DIR="$ROOT/memory/incidents/$PROJECT"; FILE="$DIR/$SLUG.md"
mkdir -p "$DIR"; [ ! -e "$FILE" ] || { echo "error: incident already exists: $PROJECT/$SLUG" >&2; exit 1; }
TMP=$(mktemp "$DIR/.incident.XXXXXX")
cat > "$TMP" <<EOF
---
schema: harness-memory-incident.v1
project: $PROJECT
slug: $SLUG
status: open
created_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
---

# $SLUG

## Summary

$SUMMARY
EOF
mv "$TMP" "$FILE"
printf 'recorded: memory/incidents/%s/%s.md\n' "$PROJECT" "$SLUG"

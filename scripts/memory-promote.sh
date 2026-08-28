#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$#" -ge 3 ] || { echo 'usage: memory-promote.sh <project>/<slug> --scope captain|harness|project [--project <name>]' >&2; exit 2; }
ID=$1; shift; [ "$1" = --scope ] || exit 2; SCOPE=$2; shift 2; PROJECT=''
if [ "$#" -gt 0 ]; then [ "$#" -eq 2 ] && [ "$1" = --project ] || exit 2; PROJECT=$2; fi
case "$ID" in */*) SOURCE_PROJECT=${ID%%/*}; SLUG=${ID#*/} ;; *) echo 'error: incident id must be <project>/<slug>' >&2; exit 1 ;; esac
case "$SOURCE_PROJECT$SLUG$PROJECT" in *[!a-zA-Z0-9._-]*) echo 'error: invalid memory identifier' >&2; exit 1 ;; esac
SOURCE="$ROOT/memory/incidents/$SOURCE_PROJECT/$SLUG.md"
[ -f "$SOURCE" ] && [ ! -L "$SOURCE" ] || { echo "error: incident not found: $ID" >&2; exit 1; }
[ "$(sed -n 's/^status: //p' "$SOURCE" | head -1)" = open ] || { echo "error: incident is not open: $ID" >&2; exit 1; }
case "$SCOPE" in
  captain) TARGET="$ROOT/memory/captain.md" ;;
  harness) TARGET="$ROOT/memory/harness.md" ;;
  project) [ -n "$PROJECT" ] || { echo 'error: project scope requires --project' >&2; exit 1; }; TARGET="$ROOT/memory/projects/$PROJECT.md" ;;
  *) echo "error: invalid scope: $SCOPE" >&2; exit 1 ;;
esac
SUMMARY=$(awk '/^## Summary/{inside=1;next} inside && /^## /{exit} inside{print}' "$SOURCE" | sed '/./,$!d')
[ -n "$SUMMARY" ] || { echo 'error: incident summary is empty' >&2; exit 1; }
LOCK="$ROOT/.harness-state/memory-promote.lock"; mkdir -p "$ROOT/.harness-state"
mkdir "$LOCK" 2>/dev/null || { echo 'error: memory promotion is locked' >&2; exit 1; }
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT HUP INT TERM
mkdir -p "$(dirname "$TARGET")"; [ -f "$TARGET" ] || printf '# %s memory\n' "$SCOPE" > "$TARGET"
TMP=$(mktemp "$(dirname "$TARGET")/.promote.XXXXXX")
{ cat "$TARGET"; printf '\n## %s\n\n%s\n\nSource: memory/incidents/%s/%s.md\n' "$SLUG" "$SUMMARY" "$SOURCE_PROJECT" "$SLUG"; } > "$TMP"
mv "$TMP" "$TARGET"
TMP=$(mktemp "$(dirname "$SOURCE")/.promote.XXXXXX")
sed 's/^status: open$/status: promoted/' "$SOURCE" > "$TMP"; mv "$TMP" "$SOURCE"
rmdir "$LOCK"; trap - EXIT HUP INT TERM
printf 'promoted: %s -> %s\n' "$ID" "${TARGET#"$ROOT"/}"

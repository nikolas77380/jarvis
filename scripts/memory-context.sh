#!/usr/bin/env bash
# Select only durable memory valid for the requested project.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT=''; INCLUDE=false; FORMAT=text
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) [ "$#" -ge 2 ] || { echo 'error: --project needs a value' >&2; exit 2; }; PROJECT=$2; shift 2 ;;
    --include-incidents) INCLUDE=true; shift ;;
    --json) FORMAT=json; shift ;;
    *) echo 'usage: memory-context.sh [--project <name>] [--include-incidents] [--json]' >&2; exit 2 ;;
  esac
done
case "$PROJECT" in ''|*[!a-zA-Z0-9._-]*) [ -z "$PROJECT" ] || { echo "error: invalid project: $PROJECT" >&2; exit 1; } ;; esac

LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
for FILE in "$ROOT/memory/captain.md" "$ROOT/memory/harness.md"; do [ ! -f "$FILE" ] || printf '%s\n' "$FILE" >> "$LIST"; done
if [ -n "$PROJECT" ] && [ -f "$ROOT/memory/projects/$PROJECT.md" ]; then printf '%s\n' "$ROOT/memory/projects/$PROJECT.md" >> "$LIST"; fi
if [ "$INCLUDE" = true ]; then
  for DIR in "$ROOT/memory/incidents/global" "$ROOT/memory/incidents/$PROJECT"; do
    [ -d "$DIR" ] || continue
    for FILE in "$DIR"/*.md; do [ -f "$FILE" ] && grep -q '^status: open$' "$FILE" && printf '%s\n' "$FILE" >> "$LIST"; done
  done
fi
if [ "$FORMAT" = json ]; then
  jq -Rn --arg project "$PROJECT" --arg root "$ROOT/" '[inputs | {path:(sub($root;""))}] | {schema:"harness-memory-context.v1",project:$project,sources:.}' < "$LIST"
else
  while IFS= read -r FILE; do printf '\n<!-- memory-source: %s -->\n\n' "${FILE#"$ROOT"/}"; cat "$FILE"; done < "$LIST"
fi

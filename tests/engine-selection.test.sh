#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/scripts" "$TMP/repo/config/projects" "$TMP/repo/plan"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/agent-engine-lib.sh" "$TMP/repo/scripts/"
printf '%s\n' '{"defaultEngine":"codex"}' > "$TMP/repo/config/harness.json"
printf '%s\n' '{"engine":"claude"}' > "$TMP/repo/config/projects/demo.json"
printf '%s\n' '**Engine:** codex' > "$TMP/repo/plan/card.md"

(
  # shellcheck source=/dev/null
  . "$TMP/repo/scripts/herdr-runtime-lib.sh"
  # shellcheck source=/dev/null
  . "$TMP/repo/scripts/agent-engine-lib.sh"
  test "$(engine_resolve claude "$TMP/repo/plan/card.md" demo)" = claude
  test "$(engine_resolve '' "$TMP/repo/plan/card.md" demo)" = codex
  : > "$TMP/repo/plan/card.md"
  test "$(engine_resolve '' "$TMP/repo/plan/card.md" demo)" = claude
  rm "$TMP/repo/config/projects/demo.json"
  test "$(engine_resolve '' "$TMP/repo/plan/card.md" demo)" = codex
  rm "$TMP/repo/config/harness.json"
  test "$(engine_resolve '' "$TMP/repo/plan/card.md" demo)" = claude
)

echo 'engine selection tests: ok'

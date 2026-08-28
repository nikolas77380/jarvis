#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if rg -n 'HANDOFF|then /clear|after /clear|and a /clear|run scripts/handoff\.sh.*instead' \
  "$ROOT/RULES.md" "$ROOT/agents/orchestrator.md" "$ROOT/scripts/context-size.sh" \
  "$ROOT/scripts/agent-spend.sh" "$ROOT/scripts/checkpoint.sh" "$ROOT/scripts/handoff.sh" \
  "$ROOT/templates/plan-task-card.md"; then
  echo 'forced token handoff language remains' >&2
  exit 1
fi

echo 'no forced handoff tests: ok'

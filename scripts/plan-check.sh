#!/usr/bin/env bash
# plan-check.sh — every plan/*.md must be (a) tracked by git and (b) linked from plan/INDEX.md.
#
# Why: a card that exists only on disk, untracked by git and absent from plan/INDEX.md, is
# invisible to every other session and worktree — and invisible claims collide (observed on
# bridgeks: two sessions independently allocated the same legacy id for two different cards because
# one card was neither committed nor indexed). scripts/new-task.sh is the way to create a card that
# passes by construction (it commits the card and its INDEX row in one step).
#
# Both id schemes are in scope by construction: the walk covers every plan/*.md, whether a frozen
# legacy shape (`T<nn>[<letter>]`) or the session-scoped shape (`<YYMMDD-HHMM>-<NNN>-<slug>`, see
# scripts/new-task.sh). Do not narrow the glob to one shape — they coexist permanently in a project
# that adopts this scheme onto pre-existing legacy ids.
#
# Reach, stated honestly: a CI checkout materialises only committed files, so the UNTRACKED half can
# never fire in CI — no machine can see a file another machine never committed. In CI this enforces
# the INDEXED half; the untracked half fires locally (pre-commit hook, scripts/new-task.sh, manual
# runs). That asymmetry is inherent to the failure it guards against, not a gap in this script.
#
# Usage: scripts/plan-check.sh          exits 0 when clean, 1 with a list of offenders otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f plan/INDEX.md ] || {
  echo "plan-check: plan/INDEX.md not found — run from a full checkout" >&2
  exit 2
}

problems=0

# (a) untracked: a card only this working tree can see.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  echo "UNTRACKED  $f — exists only in this working tree; no other session or worktree can see it."
  problems=$((problems + 1))
done < <(git ls-files --others --exclude-standard -- 'plan/*.md')

# (b) unindexed: a card no session reading the index will ever open. INDEX rows link cards as
# [id](<file>.md), so a fixed-string match on "](<file>)" is the row's existence.
for f in plan/*.md; do
  base="${f#plan/}"
  case "$base" in
    INDEX.md | TEMPLATE.md) continue ;;
  esac
  if ! grep -qF "]($base)" plan/INDEX.md; then
    echo "UNINDEXED  $f — no row in plan/INDEX.md links it; sessions read the index first and will never find it."
    problems=$((problems + 1))
  fi
done

if [ "$problems" -gt 0 ]; then
  echo
  echo "plan-check: $problems problem(s). Every plan card must be committed AND have a row in plan/INDEX.md" >&2
  echo "the moment it exists — scripts/new-task.sh does both in one commit for new cards." >&2
  exit 1
fi

echo "plan-check: ok — every plan/*.md is tracked and indexed"

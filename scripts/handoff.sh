#!/usr/bin/env bash
# Close a planning session cleanly and print the opening message for the next one.
#
# Why: "end the session early" only works if the state was written down first. A session that clears
# without updating its card takes its context to the grave and the next one starts from nothing.
# This checks the three things that must be true, then hands you the exact prompt to paste.
#
# Usage: scripts/handoff.sh T03
#        scripts/handoff.sh T03 --quiet   # prompt only, for piping

set -euo pipefail

TASK="${1:-}"
QUIET="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -z "$TASK" ]; then
  echo "usage: $(basename "$0") <task-id>   e.g. $(basename "$0") T03" >&2
  exit 64
fi

card="$(ls plan/"$TASK"-*.md 2>/dev/null | head -1 || true)"
if [ -z "$card" ]; then
  echo "no card matching plan/$TASK-*.md — create it before handing off" >&2
  exit 66
fi

problems=0
note() { printf '  %s %s\n' "$1" "$2"; }

if [ "$QUIET" != "--quiet" ]; then
  echo "handoff check for $TASK — $card"

  # 1. the card must carry this session's state, i.e. it changed and is not still 'in-progress' by accident
  if git diff --quiet HEAD -- "$card" 2>/dev/null && ! git status --porcelain -- "$card" | grep -q .; then
    note "!!" "the card is unchanged in this working tree — did this session write what it learned?"
    problems=$((problems + 1))
  else
    note "ok" "card has local changes"
  fi
  printf '  →  status line: %s\n' "$(grep -m1 '^\*\*Status:\*\*' "$card" || echo '(no Status line — add one)')"

  # 1b. the Next line — the field the next session EXECUTES instead of deriving. Without it the
  #     handoff prompt says "continue Tnn", and continuing is not an action.
  if [ -z "$(grep -m1 '^\*\*Next:\*\*' "$card" || true)" ]; then
    note "!!" "no '**Next:**' line — copy the header from plan/TEMPLATE.md and write the next dispatch"
    problems=$((problems + 1))
  elif grep -m1 '^\*\*Next:\*\*' "$card" | grep -q 'the literal next dispatch or command'; then
    note "!!" "'**Next:**' is still the TEMPLATE placeholder — the next session cannot act on it"
    problems=$((problems + 1))
  else
    note "ok" "card carries a '**Next:**' line"
  fi

  # 2. the overview should have an entry from today if anything happened
  today="$(date -u +%Y-%m-%d)"
  if grep -q "^## $today" OVERVIEW.md 2>/dev/null; then
    note "ok" "OVERVIEW.md has an entry from $today"
  else
    note "!!" "no OVERVIEW.md entry for $today — append one with scripts/overview-append.sh if anything happened"
    problems=$((problems + 1))
  fi

  # 3. the round ledger, so the next session does not dispatch a review past the ceiling
  echo "  →  round ledger:"
  scripts/review-rounds.sh "$TASK" 2>/dev/null | sed -n '2p' | sed 's/^/     /' || true

  echo
  if [ "$problems" -gt 0 ]; then
    echo "$problems thing(s) to fix before clearing. Nothing here is fatal — but a handoff that skips them"
    echo "hands the next session a card that lies."
    echo
  fi
  echo "Paste this into the next session (after /clear, or in a fresh 'claude --agent orchestrator'):"
  echo "---"
fi

title="$(sed -n 's/^# *//p' "$card" | head -1 | sed -E 's/^T[0-9]+ +[—-] +//')"
next_line="$(grep -m1 '^\*\*Next:\*\*' "$card" | sed -E 's/^\*\*Next:\*\* *//' || true)"
cat <<PROMPT
Read \`plan/INDEX.md\`, then \`$card\`. Continue $TASK — $title.
The card's next action is: ${next_line:-(missing — read the card and write one before acting)}
Do not open the other cards; the index carries the ordering you need.
Do no file work yourself — searches, multi-file edits and script runs go to \`deputy\`.
Re-checkpoint with \`scripts/checkpoint.sh $TASK\` as soon as an agent reports back, before dispatching the next one.
Before dispatching any review, run \`scripts/review-rounds.sh $TASK\`.
PROMPT

if [ "$QUIET" != "--quiet" ]; then
  echo "---"
  if command -v pbcopy >/dev/null 2>&1; then
    "$0" "$TASK" --quiet | pbcopy && echo "(copied to clipboard)"
  fi
fi

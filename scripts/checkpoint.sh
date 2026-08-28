#!/usr/bin/env bash
# Mid-task checkpoint: run this the moment a delegated agent reports back, BEFORE dispatching the
# next one.
#
# Why: `handoff.sh` closes a session, and it only helps if you reach the end of one. Usage limits,
# dead agent runs and /clear all happen mid-task. Whatever is not on the card at that moment is
# lost, and the next session pays to rediscover it. So the card write belongs to *receiving a
# report*, not to *closing a session* — and this script is the thing that refuses to let you skip
# it: it fails if the card's `**Next:**` line still says what it said before the report arrived.
#
# It also reports how much this session pays per turn to remember itself. That measurement is
# diagnostic; it never forces a handoff or context reset.
#
# Usage: scripts/checkpoint.sh T08
#        scripts/checkpoint.sh T08 --no-spend    # skip the transcript scan (a second or two)

set -euo pipefail

TASK="${1:-}"
NOSPEND="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -z "$TASK" ]; then
  echo "usage: $(basename "$0") <task-id> [--no-spend]   e.g. $(basename "$0") T08" >&2
  exit 64
fi

card="$(ls plan/"$TASK"-*.md 2>/dev/null | head -1 || true)"
if [ -z "$card" ]; then
  echo "no card matching plan/$TASK-*.md — a delegated run without a card has nowhere to land" >&2
  exit 66
fi

problems=0
note() { printf '  %s %s\n' "$1" "$2"; }

echo "checkpoint $TASK — $card"

# 1. The Next line: the one field a resuming session executes instead of deriving.
next="$(grep -m1 '^\*\*Next:\*\*' "$card" || true)"
if [ -z "$next" ]; then
  note "!!" "no '**Next:**' line — copy the header from plan/TEMPLATE.md and write one"
  problems=$((problems + 1))
elif printf '%s' "$next" | grep -q 'the literal next dispatch or command'; then
  note "!!" "'**Next:**' is still the TEMPLATE placeholder"
  problems=$((problems + 1))
else
  printf '  ok %s\n' "$next"
fi

# 2. It has to have moved. An unchanged card after an agent reported means the report lives only
#    in the conversation, which is exactly what a checkpoint exists to prevent.
if git diff --quiet HEAD -- "$card" 2>/dev/null && ! git status --porcelain -- "$card" | grep -q .; then
  note "!!" "card unchanged in this working tree — write what the agent reported into it now"
  problems=$((problems + 1))
else
  note "ok" "card has local changes"
fi

# 3. Where the review ledger stands, so the next dispatch cannot cross the ceiling of two.
echo "  →  round ledger:"
# Exit 2 means the ledger could not LOOK (see review-rounds.sh) — show that instead of an empty
# line. Swallowing it here would undo the whole point of it failing loudly.
ledger="$(scripts/review-rounds.sh "$TASK" 2>&1)" && ledger_rc=0 || ledger_rc=$?
if [ "$ledger_rc" -ge 2 ]; then
  printf '%s\n' "$ledger" | sed 's/^/     /'
  # An exit code no caller acts on is not a loud failure. A session that cannot read the ledger must
  # not be told it is clear to dispatch — not knowing the round count is exactly the state the
  # ceiling exists to prevent dispatching from.
  problems=$((problems + 1))
else
  printf '%s\n' "$ledger" | sed -n '2p' | sed 's/^/     /'
fi

# 4. Ownership overlaps: two active cards claiming the same file must never both be dispatched
#    (see scripts/owns-check.sh) — an overlap blocks "clear to dispatch" until one card is
#    re-scoped or sequenced.
echo "  →  ownership:"
owns="$(scripts/owns-check.sh 2>&1)" && owns_rc=0 || owns_rc=$?
if [ "$owns_rc" -ne 0 ]; then
  printf '%s\n' "$owns" | sed 's/^/     /'
  problems=$((problems + 1))
else
  printf '%s\n' "$owns" | sed 's/^/     /'
fi

# 5. What this session costs per turn to remember itself.
if [ "$NOSPEND" != "--no-spend" ]; then
  echo "  →  lead context:"
  scripts/agent-spend.sh 2>/dev/null | grep -E 'lead context re-read' | sed 's/^/     /' || true
fi

echo
if [ "$problems" -gt 0 ]; then
  echo "$problems thing(s) to fix before dispatching anything else."
  exit 1
fi
echo "Clear to dispatch."

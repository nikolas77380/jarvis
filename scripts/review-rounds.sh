#!/usr/bin/env bash
# The round ledger: review rounds per task, counted from what actually RAN, cross-checked against
# what the plan card recorded.
#
# Why it counts runs and not just cards: the round ceiling was a rule addressed to the lead, and the
# lead is also told to end its session early — so nothing remembered the count. Cards are supposed to
# record each round, but on 2026-08-20 a card showed one round for a PR that had had five reviewer
# runs. A ledger that trusts the write-up inherits the write-up's optimism.
#
# Card convention (still required — it is what a fresh session reads first):
#     ## Review round N (<reviewer>, <date>): <VERDICT>
#     ## Fix round N (<date>): <one line>
#
# Usage: scripts/review-rounds.sh [T02]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WANT="${1:-}" ROOT="$ROOT" \
PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}" \
CEILING="${REVIEW_ROUND_CEILING:-2}" python3 - <<'PY'
import json, os, glob, re, sys

root     = os.environ["ROOT"]
want     = os.environ["WANT"]
projects = os.environ["PROJECTS"]
ceiling  = int(os.environ["CEILING"])

# --- what actually ran: reviewer subagents, grouped by the PR number in their description ---
observed = {}
slug = os.path.basename(root)
for meta in glob.glob(os.path.join(projects, "*", "*", "subagents", "*.meta.json")):
    if slug not in meta:
        continue
    try:
        m = json.load(open(meta))
    except Exception:
        continue
    if "reviewer" not in (m.get("agentType") or ""):
        continue
    desc = m.get("description") or ""
    for n in set(re.findall(r"(?:PR|pr|#)\s*#?(\d{1,4})", desc)):
        observed.setdefault(n, []).append((m.get("agentType"), desc[:44]))

cards = sorted(glob.glob(os.path.join(root, "plan", "T[0-9][0-9]-*.md")))  # T01-slug.md only — not TEMPLATE.md
if not cards:
    sys.exit("no task cards in plan/")

print(f"{'task':6} {'PR':>5} {'recorded':>9} {'ran':>4} {'fixes':>6}  state")
breached = False

for card in cards:
    base = os.path.basename(card)
    tid  = base.split("-")[0]
    if want and tid != want:
        continue
    text = open(card, encoding="utf-8").read()

    recorded = len(re.findall(r"(?m)^## +Review round \d+", text))
    fixes    = len(re.findall(r"(?m)^## +Fix round \d+", text))
    # The PR must be DECLARED on its own line, not mentioned in prose: cards cross-reference each
    # other's PRs constantly, and a loose match attributed #14's rounds to three different tasks.
    pr = None
    m = re.search(r"(?m)^\**PR\**:?\s*#(\d{1,4})", text)
    if m:
        pr = m.group(1)
    ran = len(observed.get(pr, [])) if pr else 0

    effective = max(recorded, ran)
    if effective > ceiling:
        state = f"OVER CEILING by {effective - ceiling} — stop dispatching full reviews"
        breached = True
    elif effective == ceiling:
        state = "CEILING — the lead reads the findings itself now"
        breached = True
    elif effective == ceiling - 1:
        state = "one round left"
    else:
        state = "ok"

    if pr and ran != recorded:
        state += f"  [card says {recorded}, transcripts say {ran} — fix the card]"
    elif not pr:
        state += "  [no `PR: #n` line in the card — add one so rounds can be counted]"

    print(f"{tid:6} {('#'+pr) if pr else '—':>5} {recorded:>9} {ran:>4} {fixes:>6}  {state}")

print()
print(f"Ceiling: {ceiling} review rounds per task. Past it, the lead reads the findings itself and either")
print("dispatches a TARGETED check of one hunk or takes the decision to the user — a third full review")
print("re-reads what two reviewers already read. Every review brief must state \"round N of "
      f"{ceiling}\" and name")
print("the previous round's tip; if the card does not record N, fix the card before dispatching.")

raise SystemExit(1 if breached else 0)
PY

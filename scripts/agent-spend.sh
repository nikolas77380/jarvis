#!/usr/bin/env bash
# What the agent pipeline consumed on a given day, split by role.
#
# Why: the pipeline's biggest line item is the lead planning session re-reading its own
# conversation, and "keep planning sessions short" is a habit that nothing enforces. This makes it
# checkable — run it at the end of a day and look at the `lead` share.
#
# Usage:  scripts/agent-spend.sh [YYYY-MM-DD] [project-substring]
#         scripts/agent-spend.sh                 # today, all projects
#         scripts/agent-spend.sh 2026-08-19      # one day, all projects
#         scripts/agent-spend.sh 2026-08-19 bridgeks
#
# Figures are token-cost EQUIVALENTS from local transcripts, not an invoice: on a Team plan the
# real unit is a share of the weekly limit. Sonnet 5 is priced at its intro rate (through
# 2026-08-31); after that raise SONNET_IN/OUT to 3/15.

set -euo pipefail

DAY="${1:-$(date -u +%Y-%m-%d)}"
FILTER="${2:-}"
ROOT="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

[ -d "$ROOT" ] || { echo "no transcript directory at $ROOT" >&2; exit 66; }

DAY="$DAY" FILTER="$FILTER" ROOT="$ROOT" python3 - <<'PY'
import json, os, glob, collections

day     = os.environ["DAY"]
filt    = os.environ["FILTER"]
root    = os.environ["ROOT"]

OPUS_IN, OPUS_OUT     = 5.0, 25.0
SONNET_IN, SONNET_OUT = 2.0, 10.0   # intro rate, see header

# On bridgeks the orchestrator moved from opus to a "fable" model tier on 2026-08-21 and is
# still there; the logic-tier reviewers made the same move and were moved BACK to opus at
# effort xhigh on 2026-08-26. Do not read either as current - check the agent definitions. Fable is priced here at the opus rate because that figure is NOT VERIFIED -- an
# unverified number in a cost report is worse than an obvious placeholder, so it is named rather
# than hidden in an else-branch. Correct it when the real rate is known; until then read fable rows
# as an UPPER BOUND.  # project-specific: adjust or drop the "fable" tier name/date to match your project's model roster
#
# The handoff signal this script exists for does not depend on any of it: the 400k threshold is
# cache-read tokens per lead message, which is measured, not priced. Only the dollar columns carry
# the assumption.
FABLE_IN, FABLE_OUT   = OPUS_IN, OPUS_OUT   # UNVERIFIED -- see above

def rates(model: str):
    if "sonnet" in model:
        return (SONNET_IN, SONNET_OUT)
    if "fable" in model:
        return (FABLE_IN, FABLE_OUT)
    return (OPUS_IN, OPUS_OUT)

def cost(model, inp, out, cw, cr):
    ri, ro = rates(model)
    # cache write bills at 1.25x input, cache read at 0.1x
    return (inp * ri + out * ro + cw * ri * 1.25 + cr * ri * 0.1) / 1e6

by_role  = collections.defaultdict(collections.Counter)
by_agent = collections.defaultdict(collections.Counter)

for proj in sorted(os.listdir(root)):
    pdir = os.path.join(root, proj)
    if not os.path.isdir(pdir) or (filt and filt not in proj):
        continue
    for path in glob.glob(os.path.join(pdir, "**", "*.jsonl"), recursive=True):
        meta = path[:-6] + ".meta.json"
        agent = "lead session"
        if os.path.exists(meta):
            try:
                agent = json.load(open(meta)).get("agentType", "?")
            except Exception:
                agent = "?"
        role = ("lead" if agent == "lead session"
                else "reviewer" if "reviewer" in agent
                else "agent")
        try:
            fh = open(path, encoding="utf-8")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if not (e.get("timestamp") or "").startswith(day):
                    continue
                msg = e.get("message") or {}
                u = msg.get("usage") or {}
                if not u:
                    continue
                model = msg.get("model") or "opus"
                c = cost(model, u.get("input_tokens", 0), u.get("output_tokens", 0),
                         u.get("cache_creation_input_tokens", 0), u.get("cache_read_input_tokens", 0))
                for bucket, key in ((by_role, role), (by_agent, f"{agent} ({proj.split('-')[-1]})")):
                    b = bucket[key]
                    b["usd"]  += c * 1000        # keep integer-ish precision, divide at print
                    b["out"]  += u.get("output_tokens", 0)
                    b["read"] += u.get("cache_read_input_tokens", 0)
                    b["msgs"] += 1

total = sum(v["usd"] for v in by_role.values()) / 1000
if total == 0:
    print(f"no agent activity recorded for {day}" + (f" in *{filt}*" if filt else ""))
    raise SystemExit(0)

print(f"{day}{'  ·  ' + filt if filt else ''}   total ${total:,.2f}   (token-cost equivalent)")
print()
print(f"{'role':10} {'$':>9} {'share':>7} {'msgs':>6} {'output':>10} {'cache read':>14}")
for role in ("lead", "reviewer", "agent"):
    c = by_role.get(role)
    if not c:
        continue
    usd = c["usd"] / 1000
    print(f"{role:10} {usd:>9,.2f} {usd/total*100:>6.1f}% {c['msgs']:>6} {c['out']:>10,} {c['read']:>14,}")

print()
print(f"{'who':34} {'$':>9} {'msgs':>6} {'read/msg':>10}")
for name, c in sorted(by_agent.items(), key=lambda kv: -kv[1]["usd"])[:12]:
    usd = c["usd"] / 1000
    print(f"{name[:34]:34} {usd:>9,.2f} {c['msgs']:>6} {c['read']//max(c['msgs'],1):>10,}")

lead = by_role.get("lead")
if lead and lead["msgs"]:
    per = lead["read"] // lead["msgs"]
    print()
    print(f"lead context re-read: {per:,} tokens per message"
          f"  (${lead['read']*0.1*OPUS_IN/1e6:,.2f} of the lead's cost is re-reading itself)")
PY

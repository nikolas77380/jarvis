#!/usr/bin/env bash
# How big the current session's context is, what it is made of, and the same for every subagent it
# dispatched.
#
# Context size is not the transcript's length: it is what gets sent on the next turn, which is the
# last assistant message's input + cache-read + cache-write tokens. That number is re-read on every
# later turn, which is why it — not output length — is what a long session costs.
#
# Two things this separates that a single "tool traffic" number does not, and must:
#
#   delegation  — Agent dispatches, SendMessage follow-ups, task output. This is the lead DOING ITS
#                 JOB. A brief is long on purpose; a fresh agent starts with zero context.
#   own work    — Read/Write/Edit/Bash/Grep and friends: file work done in the conversation instead
#                 of in a subagent. THIS is the number the "lead does no file work" rule is about.
#
# Reported as one share of tool traffic each, because on 2026-08-20 a lead session showed 77% tool
# traffic and read as an emergency, while only 15% of that was its own file work — the rest was
# fifteen dispatches and their briefs. The warning now fires on own work, not on the sum.
#
# Usage:
#   scripts/context-size.sh                  # newest session for this project, with its subagents
#   scripts/context-size.sh --no-agents      # lead only (skips parsing subagent transcripts)
#   scripts/context-size.sh <transcript.jsonl>
#   scripts/context-size.sh --statusline     # one line, reads Claude Code's status JSON on stdin
#
# Money per agent is scripts/agent-spend.sh's job — this one counts tokens and stays priceless.
#
# Status bar wiring, in .claude/settings.json:
#   { "statusLine": { "type": "command", "command": "scripts/context-size.sh --statusline" } }

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-report}"
STDIN_JSON=""
if [ "$MODE" = "--statusline" ]; then
  STDIN_JSON="$(cat || true)"
fi

MODE="$MODE" ARG="${1:-}" ROOT="$ROOT" STDIN_JSON="$STDIN_JSON" \
PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}" python3 - <<'PY'
import json, os, glob

mode     = os.environ["MODE"]
arg      = os.environ["ARG"]
root     = os.environ["ROOT"]
projects = os.environ["PROJECTS"]
raw      = os.environ.get("STDIN_JSON") or ""

WINDOW = 1_000_000   # Opus 5 / Sonnet 5 context window

# Tool names that ARE the delegation, vs tool names that are work done here instead of there.
# Anything unlisted (AskUserQuestion, ToolSearch, Skill, Artifact, ReportFindings, …) is neither and
# lands in "other" — it is neither a brief nor a file edit, and lumping it into either would lie.
DELEGATION = {"Agent", "SendMessage", "TaskOutput", "TaskStop", "Workflow"}
OWN_WORK   = {"Read", "Write", "Edit", "MultiEdit", "NotebookEdit", "Bash", "BashOutput",
              "KillShell", "Grep", "Glob", "LS", "WebFetch", "WebSearch"}

def bucket(name):
    if name in DELEGATION:
        return "deleg"
    if name in OWN_WORK or name.startswith("mcp__"):
        return "own"
    return "other"

def project_dir(path):
    return os.path.join(projects, path.replace("/", "-"))

def parse(path):
    """One transcript → its next-request size, turn count, and what its traffic is made of."""
    ctx = None
    model = None
    turns = 0
    read_total = 0
    chars = {"deleg": 0, "own": 0, "other": 0, "asst": 0, "user": 0}
    id2name = {}
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return None
    with fh:
        for line in fh:
            if '"usage"' not in line and '"tool_result"' not in line and '"role"' not in line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            msg = e.get("message") or {}
            role = msg.get("role")
            if role == "assistant":
                u = msg.get("usage") or {}
                size = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                        + u.get("cache_creation_input_tokens", 0))
                if size:
                    ctx = size
                    read_total += size
                    turns += 1
                    model = msg.get("model") or model
            content = msg.get("content")
            if isinstance(content, str):
                chars["user" if role == "user" else "asst"] += len(content)
                continue
            if not isinstance(content, list):
                continue
            for b in content:
                if not isinstance(b, dict):
                    continue
                t = b.get("type")
                if t == "tool_use":
                    name = b.get("name") or "?"
                    id2name[b.get("id")] = name
                    chars[bucket(name)] += len(json.dumps(b.get("input") or {}, ensure_ascii=False))
                elif t == "tool_result":
                    c = b.get("content")
                    if isinstance(c, str):
                        s = c
                    elif isinstance(c, list):
                        s = "".join((x.get("text") or "") for x in c if isinstance(x, dict))
                    else:
                        s = ""
                    chars[bucket(id2name.get(b.get("tool_use_id"), "?"))] += len(s)
                elif t == "text":
                    chars["asst" if role == "assistant" else "user"] += len(b.get("text") or "")
    if ctx is None:
        return None
    tool = chars["deleg"] + chars["own"] + chars["other"]
    total = tool + chars["asst"] + chars["user"] or 1
    return {
        "ctx": ctx, "turns": turns, "read_total": read_total, "model": model,
        "chars": chars, "tool": tool, "total": total,
        "tool_share": tool / total * 100,
        "own_share":  chars["own"] / total * 100,
        "deleg_of_tool": chars["deleg"] / tool * 100 if tool else 0.0,
        "own_of_tool":   chars["own"] / tool * 100 if tool else 0.0,
    }

def short_model(m):
    if not m:
        return "?"
    m = m.replace("claude-", "")
    for k in ("opus", "sonnet", "haiku", "fable"):
        if k in m:
            return k
    return m.split("-")[0]

# --- locate the lead transcript --------------------------------------------
transcript, model_name, extra = None, None, ""
if raw.strip():
    try:
        st = json.loads(raw)
    except ValueError:
        st = {}
    transcript = st.get("transcript_path") or st.get("transcriptPath")
    m = st.get("model")
    if isinstance(m, dict):
        model_name = m.get("display_name") or m.get("id")
    elif isinstance(m, str):
        model_name = m
    cost = st.get("cost")
    if isinstance(cost, dict):
        usd = cost.get("total_cost_usd") or cost.get("total_cost")
        if isinstance(usd, (int, float)):
            extra = f" · ${usd:.2f}"
    if not transcript:
        sid = st.get("session_id") or st.get("sessionId")
        cwd = st.get("cwd") or (st.get("workspace") or {}).get("current_dir") or root
        if sid:
            hit = glob.glob(os.path.join(project_dir(cwd), f"{sid}.jsonl"))
            transcript = hit[0] if hit else None

if arg.endswith(".jsonl"):
    transcript = arg

if not transcript or not os.path.exists(transcript):
    cands = glob.glob(os.path.join(project_dir(root), "*.jsonl"))
    if not cands:
        print("no transcript found" if mode != "--statusline" else "context ?")
        raise SystemExit(0)
    transcript = max(cands, key=os.path.getmtime)

lead = parse(transcript)
if lead is None:
    print("no usage recorded yet" if mode != "--statusline" else "context 0")
    raise SystemExit(0)

pct = lead["ctx"] / WINDOW * 100

# --- the subagents this session dispatched ---------------------------------
agents = []
if mode != "--no-agents":
    sub_dir = os.path.join(os.path.dirname(transcript),
                           os.path.basename(transcript)[:-len(".jsonl")], "subagents")
    for f in sorted(glob.glob(os.path.join(sub_dir, "agent-*.jsonl"))):
        st = parse(f)
        if st is None:
            continue
        meta = {}
        mp = f[:-len(".jsonl")] + ".meta.json"
        if os.path.exists(mp):
            try:
                meta = json.load(open(mp, encoding="utf-8"))
            except (ValueError, OSError):
                meta = {}
        st["name"] = meta.get("agentType") or "agent?"
        st["note"] = meta.get("description") or ""
        agents.append(st)
    agents.sort(key=lambda a: -a["read_total"])

tree_read = lead["read_total"] + sum(a["read_total"] for a in agents)

if mode == "--statusline":
    label = model_name or short_model(lead["model"])
    flag = ""
    if lead["own_share"] >= 35:
        flag = "  ⚠ own file work"
    n = f" · {len(agents)} ag" if agents else ""
    print(f"{label} · ctx {lead['ctx']/1000:.0f}k ({pct:.0f}%) · tools {lead['tool_share']:.0f}%"
          f" (own {lead['own_share']:.0f}%){n}{extra}{flag}")
    raise SystemExit(0)

def bar(share, width=28):
    n = max(0, min(width, round(share / 100 * width)))
    return "█" * n + "·" * (width - n)

def m(tokens):
    return f"{tokens/1e6:.1f}M" if tokens >= 1e6 else f"{tokens/1000:.0f}k"

print(f"transcript : {os.path.basename(transcript)}")
print(f"model      : {model_name or short_model(lead['model'])}   ({lead['turns']} assistant turns)")
print()
print(f"context now: {lead['ctx']:>10,} tokens   {pct:5.1f}% of the {WINDOW//1000}k window")
print(f"             every later turn re-reads this — at $0.50/Mtok that is "
      f"${lead['ctx']*0.5/1e6:.2f} per turn just to remember")
print()
print("the lead conversation is made of (by characters):")
for name, key in (("delegation (briefs)", "deleg"),
                  ("own file work", "own"),
                  ("other tools", "other"),
                  ("assistant replies", "asst"),
                  ("your messages", "user")):
    chars = lead["chars"][key]
    share = chars / lead["total"] * 100
    print(f"  {name:20} {bar(share)} {share:5.1f}%  {chars:>9,} chars")
print(f"  {'':20} tool traffic {lead['tool_share']:.0f}% of the conversation — "
      f"{lead['deleg_of_tool']:.0f}% of it delegation, {lead['own_of_tool']:.0f}% own work")

if agents:
    print()
    print(f"this session's agents ({len(agents)}), by context re-read:")
    print(f"  {'agent':22} {'model':7} {'turns':>5} {'ctx now':>8} {'re-read':>8} {'share':>6}"
          f" {'tools':>6} {'own':>5}  what")
    rows = [dict(lead, name="lead (this session)", note="")] + agents
    for a in rows:
        share = a["read_total"] / tree_read * 100 if tree_read else 0
        note = a["note"][:34]
        print(f"  {a['name'][:22]:22} {short_model(a['model']):7} {a['turns']:>5}"
              f" {m(a['ctx']):>8} {m(a['read_total']):>8} {share:>5.0f}%"
              f" {a['tool_share']:>5.0f}% {a['own_share']:>4.0f}%  {note}")
    print(f"  {'':22} {'':7} {'':5} {'':8} {m(tree_read):>8}  100%")
    print()
    print("  re-read = every turn's context summed: the cost of the session remembering itself.")
    print("  share   = of this session tree. If the lead's share is the largest single one, the work")
    print("            is in the wrong place — that is one conversation carrying what agents should.")
    print("  own     = file work done in that context. High in an engineer is correct; high in the")
    print("            lead is the thing to move to `deputy`. Money per agent: scripts/agent-spend.sh")

    biggest = max(agents, key=lambda a: a["read_total"])
    if biggest["read_total"] > lead["read_total"]:
        print()
        print(f"  Note: `{biggest['name']}` re-read more context than the lead did"
              f" ({m(biggest['read_total'])} over {biggest['turns']} turns).")
        print("  A subagent that outgrows the lead was given more than one task's worth of work —"
              " it is the")
        print("  same quadratic curve, just moved. Split the brief, not the session.")

print()
if lead["own_share"] >= 35:
    print(f"Own file work is {lead['own_share']:.0f}% of this conversation. That is the lead doing what")
    print("`deputy` exists for — searches, multi-file edits, script debugging. Delegate it and only a")
    print("15-line summary lands here; the tool traffic dies with the subagent.")
elif lead["tool_share"] >= 55:
    print(f"Tool traffic is {lead['tool_share']:.0f}%, but {lead['deleg_of_tool']:.0f}% of it is delegation —"
          " briefs and follow-ups, not")
    print("file work. That is the lead doing its job; the number to watch here is `own`, currently"
          f" {lead['own_share']:.0f}%.")
if lead["deleg_of_tool"] >= 40 and lead["chars"]["deleg"] > 60_000:
    print()
    print(f"Briefs and follow-ups are {lead['chars']['deleg']:,} chars of this conversation. A brief")
    print("belongs in the card's `## Brief` section — dispatch by pointing at the committed card path")
    print("and the agent reads it in ITS context, not yours.")
PY

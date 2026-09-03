# Overview

Newest first. What actually happened, one entry per event — decisions, merges, measurements,
reversals. The plan (what we intend) lives in `plan/`; this file is the record (what occurred).

Keep **8-10 entries** here; move older ones to `docs/overview-archive/YYYY-MM.md`. Append with
`scripts/overview-append.sh`, never by reading the file first.

<!-- entries: new ones are inserted directly below this line -->

## 2026-09-03 — Capability-aware design QA merged

PR #5 merged as b7f3706 after two review rounds and targeted parser verification. Herdr now inherits Claude project-scoped MCP consent into task worktrees, runs declared capability preflight before substantive briefs, fails closed, and forbids the lead from proxying specialist evidence.

## 2026-09-02 — Root-project adapter merged

PR #2 was targeted-verified after the two-round ceiling and squash-merged as 7bb4828. Jarvis now treats reserved project id `jarvis` as the harness root, supports root plan cards, and refuses fleet mutation from linked Jarvis task worktrees while keeping read-only inspection available.

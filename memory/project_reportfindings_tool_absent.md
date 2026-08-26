---
name: reportfindings-tool-absent
description: Never name a tool in a brief without confirming it exists in the agent's environment; if an inherited brief names a missing tool, say so in the return so the omission is not read as a skipped step
metadata:
  type: project
---

A review brief can carry inherited boilerplate naming a specific tool for reporting findings (e.g.
`ReportFindings`) that does not actually exist in the agent's environment. Observed on bridgeks,
2026-08-26 (confirmed while reviewing PR #79): a tool-search for it returned no match, and a keyword
search surfaced only unrelated tools. Chasing it cost two lookup round-trips before the actual
reporting could start.

**Why:** the instruction was inherited from an earlier version of the brief template and never
verified against what the agent's environment actually offers. This is a general risk, not a
one-off: any brief that names a tool by name is making a factual claim about the environment, and
that claim can go stale exactly like any other.

**How to apply:** do not spend more than one lookup chasing a named tool. If it is not there, put the
ranked findings directly in the return message and in the report file (which is what the orchestrator
actually reads), and say in the return that the named tool was unavailable so the omission is read as
a corrected instruction, not a skipped step. Re-check only if a later brief claims the tool was newly
added. General rule for briefs going forward: never name a tool without confirming it exists in the
target agent's environment first.

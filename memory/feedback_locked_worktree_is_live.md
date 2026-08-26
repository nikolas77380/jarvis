---
name: locked-worktree-is-live
description: Before re-dispatching a task whose card says "dispatched", check for a CONCURRENT lead session and treat a locked worktree as a live agent — never remove it; a duplicated dispatch produced two PRs for one task on bridgeks (2026-08-25)
metadata:
  type: feedback
---

A worktree-list entry marked **locked** is a live agent, not a dead run — even at the base commit
with zero diff (it can be mid-install). Never unlock or remove it, and never re-dispatch the card it
belongs to without first checking for another lead session (peer sessions, commits on the plan branch
you did not make, a fresh agent run for that task in spend logs).

**Why:** Observed on bridgeks, 2026-08-25 — resuming from a handoff prompt, a card read as
"dispatched" was actually a live claim by a peer lead session. The resuming session removed the
locked worktree and re-dispatched. Result: two PRs and two review pipelines for one card, with the
duplicated agent work in the range of ~1M tokens. A card-ownership check did not catch it — it guards
cards against each other, not one card against two leads.

**How to apply:** a card whose status is `in-progress`/"dispatched" with no PR yet is a live claim by
default. Confirm the claimant is gone (no peer session busy on the repo, no locked worktree, no fresh
run in spend logs) BEFORE treating it as a dead run — and say in the report what was checked.
Retry-once applies only to runs proven dead.

**The other side of the same incident:** when your OWN engineer reports its worktree was removed
from under it, that is not random infrastructure death — someone removed it, and "someone" is almost
always a concurrent lead session on the same card. Before a retry-once, check for a peer session and
a PR already open on the same card; a hasty retry can produce a second, redundant PR while the first
already exists, and only a peer message stopped a second review pipeline in this incident. Retry-once
is for runs proven dead, not for runs proven killed.

**A card marked "open" is not proof either.** Resuming from a handoff prompt naming two tasks as
unblocked, a lead read both cards as untouched and started planning both in parallel — while a peer
session was already writing the briefs and had already locked worktrees for both. The cards flipped
to `in-progress` on disk mid-session; nothing was double-dispatched only because the flip landed
first. Cost: a redundant planning session plus redundant fact-finding runs.

**Sharpened rule:** the FIRST command of a resumed session, before reading any card or asking the
user anything, is a check for locked worktrees plus a check for uncommitted/unpulled changes to the
plan directory (a card modified on disk that this session did not touch = a peer mid-write). Any hit
→ stop and ask the user which session owns the task; do not plan it in parallel "just in case".

**Nuance — the lock names the LEAD's process, not the agent's.** A worktree-isolated agent's
worktree is typically locked with a reason naming the orchestrating lead session's process, not the
agent's own. So a locked worktree tells you which lead owns it, not whether the agent itself is still
running. Consequences: (1) in your own session, the agent's completion notification is the signal it
finished — the worktree can stay locked until the session ends, and the agent usually cannot remove
its own; once the notification has arrived and the branch is pushed and clean, the lead removes the
worktree itself, often after the lock has already released. (2) In a peer's session the lock is still
a live claim — the rule above stands. (3) A finished agent generally cannot be resumed once its
worktree is gone, so remove worktrees only AFTER deciding no fix round will reuse that agent's
context — re-briefing a fresh agent from scratch for the same fix round that the original could have
done warm cost roughly 195k tokens in one observed case.

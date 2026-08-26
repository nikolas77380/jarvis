---
name: worktrees-must-be-removed-after-work
description: The user deletes stale worktrees by hand when they pile up, which can kill a live agent's worktree; agent runs must remove their own worktree once the PR is open, and the lead must name live runs before any sweep
metadata:
  type: feedback
---

Every engineer / general-purpose run must remove its own worktree once its branch is pushed and the
PR is open; nothing under the worktrees directory may be left to accumulate.

**Why:** Observed on bridgeks, 2026-08-26 — the user's words (translated): "I deleted them because
we create worktrees and never remove them after the work, and then it is a mess with these
worktrees." A manual sweep that day deleted the live worktree of an in-progress run despite its
`locked` marker; the agent lost a file and had to restore from git's worktree metadata. The `locked`
marker protects against automatic pruning, not against a manual delete.

**How to apply:** (1) When briefing an implementation agent with worktree isolation, say explicitly:
remove the worktree after the PR is open. (2) Before the user cleans worktrees, hand them the list of
LIVE runs so they skip those. (3) Treat a worktree-cleanup policy as its own task, not as a bug in
whatever garbage-collection script exists. Related: [[feedback_locked_worktree_is_live]].

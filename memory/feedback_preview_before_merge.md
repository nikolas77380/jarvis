---
name: preview-before-merge
description: Offer the user a way to SEE a UI PR (a component catalog / running page from a reviewer's worktree) before asking for merge confirmation — they want to look, and merge is not required to look
metadata:
  type: feedback
---

When a UI PR reaches an approved verdict and awaits the user's merge confirmation, offer a preview in
the same message: start the app (or its component catalog / Storybook-equivalent) from a worktree
already at the PR tip — a reviewer's worktree usually has dependencies already installed — on a free
port, and hand over the URL. For static output, give the local-open command for the branch's file.

**Why:** Observed on bridgeks, 2026-08-25 — asked to confirm four merges, the user's reply was
"can't I look without merging?" — they assumed merge was the only way to see the work. Reviewer
worktrees were sitting there with everything installed; starting the app took one background command
and the merge decision followed immediately after they looked.

**How to apply:** for any UI-facing PR, the merge question always comes with a preview URL or a
one-line open command; stop the server after the decision. Do not start the server from the main
checkout (dev-server lock files, and the main checkout wanders between branches — see the
shared-port entry in `docs/evidence.md`) — use the reviewer's or engineer's worktree at the PR tip.

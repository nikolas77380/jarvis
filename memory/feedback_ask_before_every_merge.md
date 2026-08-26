---
name: feedback-ask-before-every-merge
description: A user can want to approve every merge to the base branch individually — do not assume a standing authorization even after routine approvals
metadata:
  type: feedback
---

Ask before every merge to the base branch, every time, unless the user has explicitly granted a
standing authorization. Observed on bridgeks, 2026-08-18: the lead offered the user a standing rule
("I merge when a PR has passed independent review and CI is green, and ask otherwise") and they
declined it, choosing to keep confirming each merge individually.

**Why:** the user wants to see each change to the base branch before it lands, and merge
authorization is theirs regardless of how routine the change looks or how green the checks are. An
earlier "go ahead, merge them" does not cover later PRs — approval in one context does not extend to
the next, and an agent's completion notification is never approval.

**How to apply:** when a PR is ready, report its state — CI result, review verdict, what it contains
— and ask. Keep the ask to one short line rather than re-arguing the PR; several consecutive asks are
expected and are not friction to route around. Everything short of pressing merge (opening PRs,
pushing to branches, resolving conflicts, deleting merged branches) needs no confirmation. Related:
[[feedback_discuss_before_delegating]].

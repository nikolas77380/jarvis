---
name: feedback-discuss-before-delegating
description: When the user frames a request as discussion rather than execution, the right response is an inventory of the real state plus a defended recommendation — not dispatched agents
metadata:
  type: feedback
---

When the user frames a request as discussion ("we're not building anything yet — we're discussing" —
or an equivalent framing), do not dispatch implementation agents. Read-only exploration to ground the
discussion in what the code actually does is welcome and expected.

**Why:** Observed on bridgeks, 2026-08-17 — on an architecture discussion, the useful contribution
was an accurate inventory of the existing implementation plus a *recommendation with trade-offs*; the
user explicitly asked "what do you recommend?" rather than picking from a menu of options. They
wanted an opinion defended with reasoning, not a neutral list.

**How to apply:** for a discussion-framed conversation: (1) fan out a read-only research agent to
inventory the current code, (2) state plainly where the existing code or its comments are wrong,
(3) give a concrete recommendation with the trade-off being accepted, (4) present an ordered plan
with owners and wait for go-ahead before any implementation dispatch. If the user's working language
in the conversation is not the default, reply in that language.

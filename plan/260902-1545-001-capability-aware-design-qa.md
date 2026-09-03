# 260902-1545-001 — capability-aware-design-qa

**Status:** open · **Owner:** deputy · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: none yet
**Next:** dispatch deputy with the inventory brief under ## Brief — deputy

<!--
HOW TO USE THIS FILE
Install it as `projects/<project>/plan/TEMPLATE.md` — INSIDE that project's own checkout — copy it to
`plan/Tnn-<slug>.md` per task, and delete this comment. Add the task's line to `plan/INDEX.md` in the
same change; cross-task ordering lives THERE, never only here.

The harness root itself is the one reserved exception: project id `jarvis` resolves to the harness
root checkout rather than `projects/jarvis` (there is no `projects/jarvis` — that name is reserved
and refused), so a root `plan/` — like this one — is legitimate and is the harness's own plan. Every
other project's plan/ still lives INSIDE that project's own checkout, never at the harness root.
Herdr creates each task's isolated worktree from that resolved checkout, and that worktree only ever
contains what is committed to that project's own repo — so the card, the claim lock under
`plan/.claims/`, and the review-rounds ledger all have to live inside the project's checkout to stay
visible across its worktrees. `task_card` in `scripts/herdr-runtime-lib.sh` finds a card by scanning
every `projects/*/plan/` plus the root `plan/`, and derives the project from WHICH one it found the
card in via `card_project` — there is no `**Project:**` header field to keep in sync by hand.

The header fields are parsed, not decoration:
  **Status:**  handoff.sh prints it back at you  (open · in-progress · in-review · blocked ·
               needs-decision · done)
  PR:          review-rounds.sh reads it with ^\**PR\**:?\s*#(\d+) — it MUST be on its own line and
               it MUST be the digits, `PR: #18`. A PR mentioned in prose is not declared, and a
               loose match once attributed one PR's review rounds to three different tasks.
  **Next:**    the literal next dispatch or command. A resuming session must be able to EXECUTE it
               without deriving it: "dispatch api-engineer with the brief under ## Brief" or "run
               scripts/review-rounds.sh T08, then dispatch round 2 against 3f91c02..HEAD with the
               two findings under ## Review round 1". "Continue T08" is not a next action.

Rewrite **Next:** every time an agent reports back, BEFORE dispatching the next one, and run
`scripts/checkpoint.sh <task>` — it fails while this line is missing or still says the placeholder
above. That write is what makes an interrupted session or a dead run cost one agent run instead of a
whole session.
-->

## What and why

Prevent the lead from ingesting and relaying external-source payloads when a specialist lacks a
required capability. Missing authenticated Figma must stop the run and route the task to a session
whose capability is verified; proxying evidence bloats lead context and compromises QA independence.

## Scope

Inventory dispatch, capability preflight, blocked-run, restart/switch, and design-QA instruction paths.

**Out of scope:** implementation in this inventory; `projects/`; credentials and secrets; files owned
by active tasks 260902-1204-001 and 260902-1411-001.

## Brief — deputy

Read-only inventory for task 260902-1545-001. Locate exact harness code and role instructions for
design-qa dispatch, MCP/capability availability, blocked choices, and stop/switch/relaunch. Define a
concrete patch and tests enforcing: the lead never fetches or absorbs external-source payloads for a
specialist; when authenticated Figma or another mandatory capability is unavailable, that run stops
and routing proceeds only to a fresh session whose preflight succeeds. A supplied evidence bundle
may only produce an explicitly degraded, non-APPROVE result. Do not edit files or inspect projects/.
Do not touch scope owned by tasks 260902-1204-001 or 260902-1411-001. Return at most 15 lines naming
files, current behavior, proposed ownership boundary, exact tests, and unresolved decisions.

## Done means

Inventory names exact implementation files, reusable primitives, and executable regression tests.

## Decisions still open

None for inventory. The invariant and degraded-result semantics are decided above.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

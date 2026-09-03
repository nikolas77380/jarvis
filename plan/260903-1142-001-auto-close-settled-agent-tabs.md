# 260903-1142-001 — auto-close-settled-agent-tabs

**Status:** open · **Owner:** deputy · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: none yet
**Next:** dispatch deputy with the read-only lifecycle inventory under ## Brief — deputy

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

Automatically close a specialist's exact recorded Herdr tab after its terminal result has been
captured and made recoverable. Completed tabs currently accumulate and require manual user cleanup.
Cleanup must never race result delivery, close a replacement generation, or hide a report before the
lead can consume it.

## Scope

Inventory the settle/wait/event-delivery lifecycle, metadata generation guards, and exact-tab close
primitive. Name the actual implementation seam before code changes.

**Out of scope:** implementation during inventory; deleting worktrees or branches; closing
orchestrator tabs; application repos; files owned by tasks 260902-1204-001 and 260902-1411-001.

## Brief — deputy

Read-only inventory for task 260903-1142-001. Trace a specialist reaching done/blocked through
`agent-wait.sh`, event persistence/delivery, lead wakeup, metadata updates, and Herdr tab cleanup.
Explain why completed tabs remain open and identify the safest enforcement point plus exact-tab
close primitive. Required ordering: capture/persist terminal result first; preserve a recoverable
report/event; close only the tab id and generation that settled; never close a newer replacement;
cleanup failure must not erase completion and must be observable/retryable. Determine from existing
resume semantics whether blocked tabs should auto-close or only done tabs. Do not edit, delete, close
tabs, or inspect projects/. Return <=15 lines naming exact files/functions, patch, tests, and any
unresolved decision.

## Done means

Inventory names executable tests for ordering, generation safety, idempotence, and cleanup failure.

## Decisions still open

Whether blocked tabs are terminal enough to auto-close; inventory resolves this from resume semantics.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

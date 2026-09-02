# 260902-1411-001 — global-js-agent-roles

**Status:** open · **Owner:** {{AGENT}} · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: none yet
**Next:** <the literal next dispatch or command — see the rules below>

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

What this delivers, and why it is worth doing now. If a decision was already taken on the user's
behalf, record it here **with its reason** — this is the only place that survives the session that
took it.

## Scope

Files and packages in scope. Then, explicitly:

**Out of scope:** what must not be touched, including files a concurrent agent owns.

## Brief — {{AGENT}}

The text to hand down verbatim: instruction, file paths, the boundary rule that applies, what is out
of scope, and "done" as commands. Written here rather than left in the conversation so the next
session dispatches it instead of rebuilding it.

## Done means

The commands that must pass, by name. If a suite can skip (missing service or env), say that a skip
counts as unverified, not green.

## Decisions still open

Anything the implementer must NOT decide alone. If this section is non-empty, the task is not ready
to hand to a cheaper tier — resolve it first or mark the card `needs-decision`.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

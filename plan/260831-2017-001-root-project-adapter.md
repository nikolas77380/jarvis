# 260831-2017-001 — root-project-adapter

**Status:** in-review · **Owner:** shell-engineer · **Blocks:** transition/wake-up and QA-flow tasks · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: #2
**Next:** run `scripts/review-rounds.sh 260831-2017-001`, then dispatch a logic-tier reviewer with `scripts/agent-review.sh 260831-2017-001 reviewer --brief-file reports/260831-2017-001-shell-engineer.md` against PR #2 (round 1 of 2)

<!--
HOW TO USE THIS FILE
Install it as `projects/<project>/plan/TEMPLATE.md` — INSIDE that project's own checkout, never at
the harness root — copy it to `plan/Tnn-<slug>.md` per task, and delete this comment. Add the task's
line to `plan/INDEX.md` in the same change; cross-task ordering lives THERE, never only here.

There is no shared plan/ at the harness root. Herdr creates each task's isolated worktree from
`projects/<project>`, and that worktree only ever contains what is committed to that project's own
repo — so the card, the claim lock under `plan/.claims/`, and the review-rounds ledger all have to
live inside the project's checkout to stay visible across its worktrees. `task_card` in
`scripts/herdr-runtime-lib.sh` finds a card by scanning every `projects/*/plan/` and derives the
project from WHICH one it found the card in — there is no `**Project:**` header field to keep in
sync by hand.

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

Make the Jarvis root checkout a first-class project with reserved id `jarvis`, so Jarvis can create
cards and delegate changes to its own runtime through the reviewed pipeline used for nested
projects. The user selected the root-project adapter over a permanent self-clone because it keeps a
single source of truth and lets the harness dogfood its own orchestration.

## Scope

Centralize physical project-path resolution, add explicit root onboarding and root plan discovery,
and preserve nested-project behavior and both task-id formats.

**Owns:** `scripts/*project*.sh`, `scripts/harness-state-lib.sh`, `scripts/herdr-runtime-lib.sh`,
`scripts/onboard-project.sh`, `scripts/new-task.sh`, `tests/*project*`, `tests/*task*`, `plan/**`,
`templates/plan-task-card.md`, `RULES.md`

**Out of scope:** reviewer/QA transition behavior, waiter lifecycle, visual-only delta routing,
fresh lead-session automation, `.edith/`, and application code under `projects/`.

## Brief — shell-engineer

Implement first-class root-project support for Jarvis. Read `RULES.md` completely. Use TDD: first
add failing tests proving that reserved project id `jarvis` resolves to the harness root, ordinary
ids still resolve to `projects/<name>`, root onboarding creates or accepts root `plan/` without a
nested clone, task lookup scans root plus nested plans and refuses an ambiguous duplicate id, and
root role/worktree resolution uses root `agents/` while leaving the main checkout untouched.

Centralize the special case in one resolver; callers must consume it rather than scatter
`if project == jarvis` branches. Preserve legacy `Tnn` and timestamp ids. Update stale template/rule
text that says root plans can never exist, limited to this contract.

Out of scope: `agent-review.sh`, `agent-wait.sh`, `agents/design-qa.md`, QA verdict routing, lead
session relaunch, `.edith/`, and nested application code. Do not merge or force-push. Commit, push,
open a PR to `main`, and write `reports/260831-2017-001-shell-engineer.md`.

## Done means

- Focused root-project tests pass.
- The actual full shell-suite command discovered from existing runners passes; skip is unverified.
- `scripts/plan-check.sh` passes for bootstrap and a root-plan fixture.
- PR is open against `main`; branch contains the report.

## Decisions still open

None. The user selected the root-project adapter and reserved id `jarvis`; a permanent self-clone is
not an acceptable end state.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

# 260831-2017-001 — root-project-adapter

**Status:** in-review · **Owner:** shell-engineer · **Blocks:** transition/wake-up and QA-flow tasks · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: #2
**Next:** run `scripts/review-rounds.sh 260831-2017-001`, then dispatch a logic-tier reviewer with `scripts/agent-review.sh 260831-2017-001 reviewer --brief-file reports/260831-2017-001-shell-engineer.md` against `92dc2ee..HEAD` plus the round-1 findings below (round 2 of 2)

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

## Review round 1 — REQUEST_CHANGES

Reviewer ran 17/17 shell tests and `scripts/plan-check.sh`, both green, and approved the centralized
resolver, duplicate refusal, reserved-name collision, both task-id formats, and nested-project
behavior at tip `92dc2ee`. Five findings, all fixed here with TDD (failing test added and confirmed
red against `92dc2ee`, then the minimal fix, then green):

1. **Fixed.** A `jarvis` task worktree is a linked worktree carrying the harness's own `scripts/`, so
   `herdr-runtime-lib.sh`'s BASH_SOURCE-derived `HARNESS_ROOT` resolved to the worktree itself,
   silently forking a second fleet. Guard added in `herdr-runtime-lib.sh`: detect a linked worktree
   (`.git` is a file) and re-resolve `HARNESS_ROOT` to the main checkout via
   `git rev-parse --path-format=absolute --git-common-dir`. Covered by
   `tests/root-project-worktree-guard.test.sh`.
2. **Fixed.** `session-start.sh` now resolves the explicit `--project jarvis` index through
   `project_root_path`, and the no-project form enumerates the root `plan/INDEX.md` under a `--
   jarvis --` section alongside every nested project.
3. **Fixed.** `fleet-snapshot.sh` now globs `plan/*.md` at the harness root in addition to
   `projects/*/plan/*.md`, so a freshly minted or torn-down root card with no runtime metadata yet
   shows up in FLEET STATE. Findings 2 and 3 are both covered by
   `tests/root-project-discovery.test.sh`.
4. **Fixed.** `task-teardown.sh`'s legacy-metadata fallback (`project_root=$HARNESS_ROOT/projects/$PROJECT`)
   is replaced with `project_root_path "$PROJECT"`, so a `jarvis`-owned task record predating the
   `project_root` field resolves correctly instead of dying. Covered by a new scenario appended to
   `tests/task-teardown.test.sh`.
5. **Fixed.** `docs/herdr-runtime.md` (State section, and the Spawn bullet under Behaviour) and
   `README.md` (nested-onboarding step 3) no longer state that a shared root `plan/` can never exist;
   both now name the reserved `jarvis` exception, matching the wording already in `RULES.md`.

Full suite: 19/19 `tests/*.test.sh` pass (17 prior + the 2 new files above); `scripts/plan-check.sh`
and `scripts/owns-check.sh` both pass. Working tree changes are bounded to the five named files plus
tests and this card — nothing under `agent-review.sh`, `agent-wait.sh`, `agents/design-qa.md`, QA
verdict routing, lead relaunch, `.edith/`, or nested application code was touched.

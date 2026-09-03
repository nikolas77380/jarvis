# Multi-project review ledger — specification

## Objective

Make `scripts/review-rounds.sh` (and its callers `scripts/checkpoint.sh` / `scripts/handoff.sh`)
correct for the harness's actual layout: multiple independent project repos under `projects/<name>/`,
each with its own `plan/`, reviewed by Herdr task-agents dispatched via `scripts/agent-spawn.sh` and
handed from engineer to reviewer via `scripts/agent-review.sh` — never native Task-tool subagents.

## Why this task exists (found 2026-08-31, dispatching review for task `260831-1348-001` in
`bridgeks-app`)

`scripts/review-rounds.sh` at harness root is a near-verbatim copy of
`projects/bridgeks-app/scripts/review-rounds.sh`, promoted to harness root without adapting it to the
multi-project / Herdr reality it now has to work in. Two concrete, reproduced bugs:

1. **Wrong project resolution.** `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` resolves
   to the directory the *script* lives in, not the project owning the task id passed as `$1`. Run from
   harness root (exactly how `checkpoint.sh`/`handoff.sh` invoke it: `scripts/review-rounds.sh
   "$TASK"`), `ROOT` is the harness root itself, which has no `plan/` directory at all — every
   project's `plan/` lives at `projects/<name>/plan/`. Reproduced: `./scripts/review-rounds.sh
   260831-1348-001` from harness root (and from `projects/bridgeks-app`, since `BASH_SOURCE` still
   points at the harness-root copy) both fail with `no task cards in plan/`. This means
   **`checkpoint.sh` and `handoff.sh`, called exactly as the orchestrator's own instructions say to
   call them, cannot currently find any project's task cards.**
2. **Wrong data source for "did a reviewer actually run".** The script globs
   `~/.claude/projects/<encoded-main-root-path>/*/subagents/*.meta.json` — Claude Code's own
   transcript directory for *native Task-tool subagents launched from an interactive session whose
   cwd is the project's main checkout*. Herdr-dispatched reviewers (`scripts/agent-review.sh`) are a
   **separate CLI session** whose cwd is the task's own worktree
   (`.harness-worktrees/<project>/<task-id>`), and they hand a task from engineer to reviewer via
   `scripts/agent-review.sh`, which already writes a purpose-built ledger:
   `$HARNESS_STATE/agent-history/<task-id>.jsonl`, one JSON line per handoff, schema
   `harness-agent-review-handoff.v1`, fields include `task`, `from`, `to` (role name), `head`, `at`.
   This ledger is keyed **exactly** by task id — no PR-number-in-free-text regex matching needed,
   which removes an entire class of ambiguity the current script works hard (and only partly
   succeeds) to resolve: multi-PR attribution, PR declared by more than one card, runs naming no PR,
   etc. `review-rounds.sh` does not read this ledger at all today.
3. **`RULES.md` never names `scripts/agent-review.sh`** as the mechanism for handing a task from
   engineer to reviewer — it describes the review tiers and round ceiling but not the actual dispatch
   command. (This one line item was fixed directly, ahead of this task, as part of unblocking task
   `260831-1348-001`'s review — see `RULES.md`'s Agent pipeline section, "hand off to review" bullet.)

The project-local copy at `projects/bridgeks-app/scripts/review-rounds.sh` is unaffected by either bug
in its own repo's context (its `ROOT` resolves correctly there, and it predates Herdr — it was built
for exactly the native-subagent model it still assumes) and has real test coverage:
`projects/bridgeks-app/scripts/test/review-rounds.test.sh` +
`projects/bridgeks-app/scripts/test/review-rounds.mutants.py`. The harness-root copy has none. Use the
project-local version's tests as the starting point — the counting/attribution logic they exercise
(partition invariants, malformed `PR:` lines, multi-card declarations, etc.) is still correct once the
input is an id-keyed ledger instead of PR-number regex matches; only the *data source* wiring changes
non-trivially.

## Fix

1. **Project resolution**: replace the `dirname(BASH_SOURCE)`-based `ROOT`/`MAIN_ROOT` logic with the
   same task-id → project resolution `scripts/agent-spawn.sh` already uses
   (`task_card`/`card_project`/`plan_card_matches` in `scripts/herdr-runtime-lib.sh`, which search
   `projects/*/plan/<id>*.md`). `review-rounds.sh` takes a task id as its one optional argument
   already (`$1`, called `WANT`) — when given, resolve straight to that task's project and its
   `plan/`; the no-argument form (scan every task, used by `checkpoint.sh`/`handoff.sh`? — verify
   actual call sites before deciding) needs to either require an id or iterate every project's
   `plan/` under `projects/*/plan/`. Check both real call sites
   (`scripts/checkpoint.sh:65`, `scripts/handoff.sh:69,109`) before choosing — they always pass
   `$TASK`, so the id-less path may be dead and removable, but confirm rather than assume.
2. **Ledger source**: replace the `subagents/*.meta.json` glob + PR-number regex extraction with a
   read of `$HARNESS_STATE/agent-history/<task-id>.jsonl` (only the file for the task(s) actually
   being counted — no cross-task globbing needed once resolution is id-keyed). Each line whose `to`
   field contains `review` (matches `nextjs-reviewer`, `nestjs-reviewer`, `mechanical-reviewer`, any
   future `*-reviewer` role; excludes `design-qa`) counts as one review-round run for that task's
   `ran` count. Keep the existing "fail loudly, never report a false zero" invariant
   (`cannot_look`/`crash_is_also_cannot_look`) — apply it to "ledger directory missing" /
   "0 parseable lines across every ledger examined", the same shape of guarantee the old code gave for
   the transcript scan.
3. **Keep or simplify the attribution/footer machinery** (the `observed`/`runs`/`in_rows`/`no_pr`/
   `undeclared`/`row_sum` block, ~lines 160–430 in the current harness-root copy) — decide during
   implementation whether the PR-number cross-checking is still worth keeping (it becomes a pure
   documentation-hygiene check — "does this card's `PR:` line agree with what actually happened" —
   rather than the thing that determines `ran`) or whether it should be simplified now that `ran` no
   longer depends on it. Do not delete it without understanding why each piece exists first — read the
   comments in place, they document real prior incidents (T21, T25, T27, M24/M24b mutants).
4. Port `projects/bridgeks-app/scripts/test/review-rounds.test.sh` and `.mutants.py` to
   harness-root `tests/`, adapted for: multi-project fixtures (at least two fake projects under a
   fixture `projects/`), the `agent-history/*.jsonl` ledger as the fixture data source instead of fake
   `subagents/*.meta.json`. Every existing scenario the current suite covers should have an equivalent
   here — do not drop coverage in translation.
5. Update `RULES.md` if the fix changes any user-visible behavior beyond what's already documented
   (e.g. if the no-argument form's semantics change).

## Explicitly out of scope

- Do not touch, delete, or rewrite anything under `projects/*/scripts/` (including
  `projects/bridgeks-app/scripts/review-rounds.sh` and its tests) — those are a separate, working,
  tested implementation for a project that predates Herdr; retiring or re-syncing them is a distinct
  decision for the user, not this task.
- Do not change `scripts/agent-review.sh`'s ledger schema — build on
  `harness-agent-review-handoff.v1` as it stands.

## Testing and boundaries

- Real end-to-end check: run `scripts/checkpoint.sh <a-real-task-id>` and
  `scripts/review-rounds.sh <a-real-task-id>` from harness root against a real project (e.g.
  `bridgeks-app`) with at least one real `agent-review.sh` handoff in its history, and confirm they
  report correctly (no `no task cards in plan/`, correct `ran` count).
- New/ported test suite must pass under harness-root `tests/`'s existing runner convention (see how
  `tests/*.test.sh` are invoked elsewhere in this repo).
- Never modify a project's `plan/` or `reports/` content as part of this task — read-only there.

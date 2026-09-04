# 260903-1142-001 — auto-close-settled-agent-tabs

**Status:** in-review · **Owner:** shell-engineer · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: #6
**Next:** dispatch reviewer (logic tier) against PR #6 at the fix-round tip for round 2 of 2 — read
only the delta since `96b3054` plus the "## Review round 1" findings below; the full suite still
runs in full.

## Inventory findings (2026-09-03)

1. **Detection**: `scripts/agent-wait.sh` loops on `herdr agent wait` + `agent_status()`
   (`scripts/herdr-runtime-lib.sh:262-266`), mapping to `working|idle|done|blocked|unknown`.
   Quota-limited "blocked" is transient and auto-relaunches via `agent-switch.sh --relaunch`.
2. **Persistence/notification**: `scripts/events-poll.sh` diffs `fleet-snapshot.sh --json` and calls
   `event_emit()` (`scripts/harness-event-lib.sh:11-25`), appending idempotent (hash-deduped) records
   to `$HARNESS_STATE/events.jsonl`. `scripts/inbox.sh list/drain/acknowledge` is how the lead
   consumes/acks; unread = events.jsonl minus event-acks.jsonl.
3. **Metadata**: task `.meta` (`tab`, `session`, `generation`, `stopped`) updated by
   `agent-spawn.sh`, `agent-switch.sh` (generation bump, `atomic_meta_write`), `agent-review.sh`
   (handoff bump), `agent-stop.sh` (`stopped=1`). `events-poll.sh` only writes `fleet-previous.json`,
   never task meta.
4. **Close primitive**: `scripts/agent-stop.sh` — `herdr --session <session> tab close <TAB>` then
   `stopped=1`. Needs `tab` + `session` from `.meta`. Generation-safety is NOT built into
   `agent-stop.sh`; the safe pattern lives in `agent-switch.sh:51` (verify `FINGERPRINT` unchanged
   before closing the old tab).
5. **Why tabs stay open**: cleanup is simply never invoked on settle. `events-poll.sh` emits
   `agent-done`/`agent-blocked` events but nothing consumes them to call `agent-stop.sh`. No code
   gate on "report consumed" exists today.
6. **blocked vs done**: only `done` is safe to auto-close. `blocked` is a live, resumable state reused
   in place by `agent-switch.sh`/`agent-review.sh`/`quota-resume-poll.sh`; closing it would destroy
   state a resume flow expects to reuse.

**Proposed enforcement point**: new step after `inbox.sh acknowledge` (or a dedicated
`agent-cleanup.sh` triggered by the lead only on `agent-done` events), reading `tab`/`generation`/
`fingerprint` from meta and calling the `agent-stop.sh` close path guarded by the
`agent-switch.sh:51` fingerprint check. Never inside `events-poll.sh` (no meta lock held there, runs
unattended).

**Tests needed**: (a) ordering — event persisted+acked before close attempted; (b) generation-safety —
close after a switch/review handoff targets only the old tab, never the new one; (c) idempotence —
double-close/double-ack is a no-op; (d) cleanup-failure observability — failed close leaves
meta/event intact, logs, and is retryable (mirror `agent-stop.sh`'s `die` on close failure without
losing the ack).

**Resolved (2026-09-03, user confirmed)**: persist done event -> acknowledge -> generation-guarded
close exact tab. Only `done` auto-closes; `blocked` stays open because resume and quota flows reuse
it in place.

## Implementation (2026-09-03)

`events-poll.sh` now resolves and freezes the producing execution's identity (agent name, tab,
session, generation) from the task's `.meta` into the `agent-done` event's new `identity` field at
the moment it observes the `done` transition (`harness-event-lib.sh`'s `event_emit` grows an
optional 5th `identity` JSON arg, default `{}`, so every other event type and the existing
`inbox.sh emit` CLI are unaffected). `scripts/agent-cleanup.sh <event-id>` is the only path that
acts on it: it requires the event to already be acknowledged and to be type `agent-done`, then
re-reads the task's current metadata under its state lock and closes only if agent name, tab,
session, and generation still match the frozen identity — any mismatch (a newer spawn, switch,
review handoff, or relaunch) is a safe no-op. Closing itself is `close_recorded_tab()`, extracted
from `agent-stop.sh` into `herdr-runtime-lib.sh` so both end in the identical `stopped=1` terminal
state; a close failure `die`s before mutating meta, so the acknowledgement and metadata stay intact
and the same command is safe to retry. Tests: `tests/agent-cleanup.test.sh` (ordering, ack-gating,
exact-target close, close-failure-then-retry, idempotent double-cleanup, generation-mismatch no-op,
blocked-never-closes) plus the full existing suite and `tests/herdr-runtime.test.sh`'s
`agent-stop.sh` coverage, unchanged behaviourally by the refactor. Documented in
`docs/herdr-runtime.md`, `docs/inbox-and-decisions.md`, and `agents/orchestrator.md`.

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

## Owns

scripts/agent-cleanup.sh, scripts/harness-event-lib.sh, scripts/events-poll.sh, scripts/agent-stop.sh,
scripts/herdr-runtime-lib.sh, tests/agent-cleanup.test.sh, docs/herdr-runtime.md,
docs/inbox-and-decisions.md

## Done means

Inventory names executable tests for ordering, generation safety, idempotence, and cleanup failure.
Implementation: `agent-cleanup.sh` exists, is the only settled-tab close path, is covered by
`tests/agent-cleanup.test.sh`, and the full shell suite plus shellcheck/plan-check/owns-check pass.

## Decisions still open

None. Resolved 2026-09-03: only `done` auto-closes (see "Resolved" above); `blocked` never does.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

## Review round 1

**Verdict:** REQUEST_CHANGES at `96b3054`. Mechanics (ack-gating, exact-tab targeting, generation
guard, idempotence, retryable close failure, blocked refusal) held under test, but two blockers sat
one level up: (1) the orchestrator rule this design hung cleanup on told the lead to run
`agent-cleanup.sh` right after acknowledging any engineer's `agent-done`, which marks the task
`stopped=1` and bricks the very next `agent-review.sh`/`agent-switch.sh` handoff ("use a relaunch
flow"); (2) the event dedup key was `type+generation` where `generation` was the literal string
`"done-$HEAD"` — a reviewer generation that commits nothing settles at the same HEAD as the engineer
generation before it, so their done events collided, silently losing the reviewer's event and
permanently orphaning the tab that actually accumulates. Medium: `docs/herdr-runtime.md` claimed
settled tabs close "automatically" when nothing invokes cleanup unattended, and called it "the only
auto-close path" when `agent-review.sh`/`agent-switch.sh` also close tabs as part of a handoff. Low:
`events-poll.sh` assembles the frozen identity from six unlocked reads of the task `.meta` (fails
safe via the generation match at close time, but the comment overclaimed a guarantee nothing
enforces); the PR's "21 files" test-count claim was arithmetic, not a measurement, and the branch
predated PR #5 so the merged tree was never actually exercised; the branch does not merge cleanly
into `origin/main` (4 conflicting docs/plan files). Full report:
`reports/260903-1142-001-reviewer.md`.

**Fix:** `56e8619` reworded the `agents/orchestrator.md` and `docs/herdr-runtime.md` rules so
`agent-cleanup.sh` is run only for a generation the lead has decided will not be handed to another
agent — never as a reflex after every acknowledged done — since `agent-review.sh`/`agent-switch.sh`
already close the outgoing tab themselves as the last step of their own handoff. `events-poll.sh` now
keys the `agent-done` dedup id on `$RUNTIME-$HEAD-g$DONE_GENERATION` (falling back to the old
`$RUNTIME-$HEAD` when no task meta is resolvable), so every execution generation gets its own event
even at an unchanged HEAD. Added `tests/agent-cleanup.test.sh` scenario 4: two generations settling
at the same HEAD emit two distinct `agent-done` events with the right frozen identity each, and only
the current generation's event can actually close its tab. Softened the unlocked-read comment in
`events-poll.sh` to describe the actual fail-safe property instead of an unenforced guarantee, and
corrected the "automatically"/"only auto-close path" claims in `docs/herdr-runtime.md` and
`docs/inbox-and-decisions.md`. Merged `origin/main` (`f7634b8`) to pick up PR #5, resolving the 4
conflicts by keeping this branch's newer content (`agents/orchestrator.md`: both rules are additive
and independent, kept both; `OVERVIEW.md`/`plan/INDEX.md`: unioned in the missing PR #5 entries;
`plan/260902-1545-001-capability-aware-design-qa.md`: an add/add conflict where this branch's own
prior commit already carried the fuller, accurate "done, PR #5 merged" content that `origin/main`'s
side lacked, kept this branch's version). Full suite on the merged tree: 25/25 (was 20 on the
pre-merge branch, 25 confirmed by round 1's own trial merge). shellcheck -S warning, plan-check, and
owns-check all clean.

**Left alone:** the six unlocked `.meta` reads in `events-poll.sh` are not moved under the task's
state lock. `harness-state-lib.sh`'s lock is a single global slot (`state_lock_acquire`/`_release`
track one `STATE_LOCK_DIR`, not a stack), and `events-poll.sh` already holds the `inbox` lock for its
whole run; nesting a per-task lock inside it with the existing helper would silently drop the `inbox`
lock's own mutual exclusion the moment the nested lock releases (a strictly worse race than the one
being fixed), for a benefit the generation/fingerprint match at close time already provides. Fixing
it properly means teaching the lock helper to stack, which is a change to `harness-state-lib.sh`
outside this task's `Owns:` and unrelated to the lifecycle/identity defects the brief asked for.

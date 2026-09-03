# 260903-1142-001 — auto-close-settled-agent-tabs

**Status:** in-review · **Owner:** shell-engineer · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: #6
**Next:** dispatch reviewer (logic tier — touches runtime metadata and the event schema) against
PR #6; round 1 of 2.

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

# 260903-1142-001 — auto-close-settled-agent-tabs

**Status:** in-progress · **Owner:** shell-engineer · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: none yet
**Next:** dispatch shell-engineer with the implementation brief under ## Implementation brief

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

None. User confirmed `persist done event -> acknowledge -> generation-guarded close exact tab`.
Only `done` auto-closes; `blocked` stays open because resume and quota flows reuse it in place.

## Inventory findings

No cleanup is invoked after settle. `events-poll.sh` persists deduplicated done/blocked events and
`inbox.sh` owns consumption/acknowledgement, while `agent-stop.sh` is the exact-tab close primitive.
The safe implementation is a dedicated cleanup step after acknowledgement of an `agent-done`
event. It must re-read metadata and verify the recorded generation/fingerprint before closing, so a
newer replacement tab cannot be killed. Close failure leaves completion/event state intact and is
observable and retryable. Tests cover persist-before-close ordering, generation safety,
idempotence, and cleanup failure. Never auto-close `blocked`.

## Implementation brief — shell-engineer

Implement task 260903-1142-001 in its existing worktree. Add an explicit settled-tab cleanup path
whose only trigger is acknowledgement by the lead of a durably persisted `agent-done` event. Do not
close on detection, event emission, unread listing, drain alone, `blocked`, `idle`, timeout, or quota
state. The persisted event must carry or resolve an immutable identity sufficient to prove the exact
session/tab/generation/fingerprint that produced it. Immediately before close, re-read current task
metadata under the appropriate lock and close only if it still matches that settled identity; a
newer spawn, switch, review handoff, or relaunch makes cleanup a safe no-op. Reuse the exact-tab close
primitive, but do not mark a newer generation stopped. Cleanup is idempotent. A close failure must
leave the completion event acknowledged/durable, keep retry information observable, return non-zero
from the cleanup action, and permit a later retry. Worktrees and branches are not deleted. Add or
update focused shell tests for: persist-before-close ordering; no close before acknowledgement;
exact tab/session target; generation/fingerprint mismatch; double acknowledgement/cleanup;
close failure then successful retry; and no cleanup for blocked. Document the lifecycle contract in
the appropriate harness runtime documentation and role rules only where operators need it. Inspect
existing event schema and helpers, but do not redesign unrelated inbox behavior. Do not touch
application repos or files owned by active tasks 260902-1204-001 and 260902-1411-001. Run all
relevant shell tests, shellcheck, plan-check, and owns-check. Commit, push, open a PR, write
`reports/260903-1142-001-shell-engineer.md`, and return <=15 lines.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

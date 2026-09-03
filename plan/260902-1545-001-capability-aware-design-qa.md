# 260902-1545-001 — capability-aware-design-qa

**Status:** in-review · **Owner:** deputy · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: #5
**Next:** hand task to deputy for targeted verification of the parser hunk at bb05695 and the two round-2 reproductions only

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

None. A child must inherit the same authorized MCP identity/configuration available to its
orchestrator. No multi-profile broker is required. Capabilities are declared in role frontmatter; a
live probe verifies inheritance before the substantive brief; failure is fail-closed and never
causes the lead to proxy specialist evidence.

## Inventory checkpoint

No preflight exists. `scripts/agent-spawn.sh` and `scripts/agent-review.sh` launch without MCP/auth
checks; `agents/design-qa.md` only asks the agent to report BLOCKED. Enforcement belongs in those
scripts plus role/orchestrator rules. Before implementation, identify the existing primitive that
can prove a target session's live capability before its substantive brief is delivered, and how the
runtime selects a different authenticated session/profile after failure.

The follow-up found that no live-auth probe or credential-profile selection exists. `engine_start`
only observes coarse terminal state and `engine_prompt` immediately sends the substantive brief.
Authentication failure appears only inside the child conversation. Existing primitives can support
a deterministic probe prompt and parsed success/failure marker before releasing the real brief.
However, `agent-switch.sh` selects only Claude versus Codex; it cannot select a different credential
identity. Automatic recovery to an authenticated agent therefore requires a new profile broker with
credential enumeration and launch-time profile selection.

## User clarification

The orchestrator already had authorized Figma access. The intended contract is therefore shared
authorization inheritance, not multiple credential profiles. Diagnose why a Herdr child sees an
unauthenticated MCP server despite the parent having working access, repair that boundary, and keep
a live preflight as a regression guard. Never print or relay credential values through lead context.

## Root cause

Claude children inherit the real HOME and keychain, but MCP consent is project-scoped by absolute
cwd in `~/.claude.json`. `scripts/agent-engine-lib.sh` creates trust state for the new worktree path
but does not inherit `mcpServers` or `enabledMcpjsonServers` from the parent project entry. Thus the
same authorized identity appears unauthenticated inside a fresh worktree.

## Implementation brief — shell-engineer

Implement task 260902-1545-001 in the existing task worktree. In
`scripts/agent-engine-lib.sh`, extend the Claude worktree initialization boundary so a newly created
worktree inherits the parent project's project-scoped MCP configuration/consent keys
`mcpServers` and `enabledMcpjsonServers` before any substantive brief is delivered. Copy locally
between JSON project entries without printing, logging, serializing into reports, or exposing any
credential/token values. Preserve unrelated child and parent configuration. Add a deterministic live
capability preflight before the substantive prompt for roles declaring required capabilities; the
role declaration must be frontmatter, not a hard-coded design-qa map. Probe failure must stop the run
fail-closed and must not deliver the substantive brief. Add the general lead invariant to
`RULES.md` and `agents/orchestrator.md`: the lead never fetches or absorbs external-source evidence
on behalf of a specialist. Update `agents/design-qa.md` so prefetched evidence without live required
capability cannot yield APPROVE/MATCH. Add regression tests covering MCP key inheritance without
printing values, preservation of unrelated config, preflight ordering, fail-closed behavior, and
the anti-proxy rule. Do not touch `projects/` or files owned by active tasks 260902-1204-001 and
260902-1411-001. Run the relevant shell test suite, lint/static checks, and plan checks. Commit,
push, open a PR, write `reports/260902-1545-001-shell-engineer.md`, and return at most 15 lines.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

## Engineer checkpoint

PR #5 at `4cd51b4`. The implementation inherits Claude project-scoped MCP consent into task
worktrees, declares required capabilities in role frontmatter, gates substantive prompts on live
preflight, fails closed, and records the anti-proxy invariant. Engineer reports 25 existing plus 5
new tests green, with `plan-check.sh` and `owns-check.sh` clean. Full report:
`reports/260902-1545-001-shell-engineer.md`. Reviewer must treat the diff as evidence.

## Review round 1

**Verdict:** NEEDS_CHANGES (reviewer response interrupted by host sleep after producing the finding).

The reviewer reran the full shell suite successfully and confirmed `plan-check.sh` and
`owns-check.sh` pass. A direct capability-parser reproduction returned capabilities containing
`figma`, but failed because another output line followed the deterministic marker. The parser must
recognize exactly one well-formed marker independent of harmless surrounding agent output, while
still rejecting missing, malformed, duplicate, or contradictory markers. Add a regression test for
trailing output. Fix round scope is this parser delta and its tests only; all other PR hunks remain
outside the reading scope for round 2.

**Fix:** `9c72c33` recognizes exactly one well-formed PASS marker anywhere in probe output and
rejects missing, malformed, duplicate, FAIL, or contradictory markers. Only
`scripts/agent-engine-lib.sh` and `tests/capability-preflight.test.sh` changed. Engineer reran the
full 24-file shell suite, plan/ownership checks, and shellcheck successfully. Report-only tip is
`b0ab6ed`; reports remain outside review scope.

## Review round 2

**Verdict:** REQUEST_CHANGES. Full suite 24/24, shellcheck, plan-check, and owns-check passed, but the
reviewer reproduced two defects through the real functions:

1. The terminal snapshot echoes the delivered preflight prompt, which itself contains literal PASS
   and FAIL marker lines. The parser counts those along with the agent reply, so an authenticated
   PASS becomes `pass_count=2`, `fail_count=1` and every capability-gated role is rejected.
2. A bare `CAPABILITY_PREFLIGHT_RESULT FAIL` is not counted because the matcher requires a trailing
   space; combined with PASS it can be accepted, violating fail-closed contradictory-marker rules.

The two-round full-review ceiling is reached. The next run may edit only the preflight
prompt/reply-boundary parser and its focused regression tests. Verification must exercise the real
prompt echo plus reply path and bare FAIL; it is targeted hunk verification, not a third full review.
Reviewer report exists uncommitted in the task worktree at
`reports/260902-1545-001-shell-reviewer.md`.

**Targeted fix:** `bb05695` changes verdict parsing to use the last well-formed marker in the echoed
snapshot, so prompt examples precede and cannot override the agent's answer. Bare FAIL is recognized.
Focused tests construct snapshots from the real prompt plus appended PASS/FAIL replies. Engineer
reports 24/24 shell test files, shellcheck, plan-check, and owns-check green. The reviewer report was
committed with the fix. The only remaining work permitted by the round ceiling is independent
verification of this parser hunk and the two exact reproductions; no full PR reread.

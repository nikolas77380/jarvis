# 260916-1454-001 — Codex completion wake without model polling

**Status:** in-review · **Owner:** lead · **Depends on:** —
**Engine:** codex
**Validation:** strict
PR: #7
**Next:** scripts/review-rounds.sh 260916-1454-001
**Owns:** scripts/codex-completion-watch.sh, scripts/codex-completion-lib.sh, tests/codex-completion.test.sh, docs/codex-completion.md, additive Codex-only instructions in agents/orchestrator.md

## Goal

A Codex lead receives a completion prompt when a Herdr specialist settles, without repeated model turns while waiting. Keep the Claude background Bash workflow unchanged. Reuse the universal agent-wait, metadata, review and validation scripts; do not create another validation pipeline.

## Decisions and boundaries

- Implement an explicit opt-in Codex watcher as an ordinary foreground shell process in a tracked Herdr tab. No nohup, shell background detachment, model polling or daemon installation.
- Existing Claude behavior, agent-wait.sh, engine startup, default session selection, Clean Slate and universal validation scripts stay unchanged. Concurrent PR #6 owns settled-tab cleanup; do not modify that work.
- Require explicit destination Herdr session and pane. Capture and validate the Codex agent session identity, never infer the recipient from UI focus. Task source session comes from canonical task metadata. Support default as well as named sessions.
- Reuse agent-wait.sh for task completion and quota recovery. Re-read final task metadata after waiting. The watcher must remain observable through durable state and its tracked tab.
- Deliver a bounded instruction containing task id and canonical report/metadata location through Herdr agent prompt, never arbitrary specialist terminal text. The lead then inspects the result and runs the existing review/validation path.
- Use a single watcher claim per task generation and recipient session identity. Repeated registration must not duplicate notifications. Reject stale recipient identity, wrong engine, stale task generation and missing metadata. Do not send into a blocked approval dialog; retain pending delivery. If the recipient is working, wait outside the model until idle/done, then revalidate identity before sending.
- Persist pending, waiting, delivering, delivered and failed/uncertain outcomes atomically. A crash during delivery cannot honestly guarantee exactly-once delivery: never automatically resend an ambiguous attempt; make reconciliation explicit. Failed command delivery must stay diagnosable rather than be marked delivered.
- No automatic tab cleanup, merge, provider changes, secrets or changes to other projects.

## Brief

Implement the opt-in Codex watcher described above in the existing Bash harness, in your isolated worktree. Read RULES.md and agents/shell-engineer.md. Start with failing tests. Use existing harness state/locking/metadata helpers and the existing mock Herdr test conventions, preserving both legacy and timestamp task ids, canonical root/nested project lookup and linked-worktree mutation guards. Keep source changes within Owns; report any required expansion before editing it. Use the installed herdr CLI help for exact syntax. The lead confirmed the actual live session is default, while the runtime default is harness; do not change that default globally.

Provide start/status/reconcile behavior in the new script so an operator can start a tracked watcher and inspect durable delivery state. The watcher must execute as a plain shell process, not another LLM. Prove that normal delivery sends one completion prompt to the captured Codex session, and registration duplicates, recipient replacement, wrong engine, blocked/busy recipients, task switch, missing task, source wait failure and ambiguous delivery do not send spurious prompts. Retain existing quota recovery via agent-wait.sh. Avoid holding shared task locks while waiting on network/Herdr or invoking a script that needs the same lock.

Use the universal tests and existing review/validation system unchanged. Read the project's available check configuration and CI to establish the real suite invocation; do not invent a parallel runner. Run focused new tests and existing agent-wait, engine-selection, quota-resume, state-lock, root-project and full shell suites. Add a Codex-only instructions paragraph explaining registration and an operational doc with failure recovery and a real Herdr smoke-test procedure. Do not claim live wake works based only on mocks.

Commit the task card and INDEX entry from /private/tmp/jarvis-codex-wake-plan (only this task; canonical checkout has unrelated dirty plan changes) into your branch as part of the implementation. Write reports/260916-1454-001-shell-engineer.md. Push and open a PR against main through gh-axi; never merge. Return <=15 lines including PR, HEAD, exact checks, remaining live verification and report path. The lead will dispatch independent review through the existing agent-review.sh path.

## Done

- Tests establish failure behavior and unchanged Claude compatibility.
- Independent logic-tier review approves; actual universal checks pass.
- An actual tracked watcher resumes the intended Codex session after a harmless task completes, without repeated model polling.
- State and docs accurately record limits, recovery and next action.

## Engineer checkpoint

PR #7 is open at implementation commit `1b84ae5`. The focused watcher matrix, requested compatibility
tests, full 20-file shell suite, static shell checks, plan check, and ownership check passed. The
original engineer run did not claim a live tracked-tab wake. Full report:
`reports/260916-1454-001-shell-engineer.md`.

## Review round 1

The reviewer requested one P1 fix at reviewed tip `33fca99`: a delivered task-level watcher claim
prevented registration after the same task advanced from engineer to reviewer or fixer. Fix commit
`2d1af26` now permits only a strictly newer canonical source generation to replace a delivered claim,
archives the prior metadata intact under the existing task lock, and continues to reject duplicate,
rollback, waiting, failed, delivering, and uncertain replacements. The regression exercises three
generations, exactly one prompt per generation, duplicate rejection for each, rollback rejection, and
preservation of archived source and recipient identities.

Focused watcher, requested compatibility, fail-fast 20-file shell suite, shellcheck, Bash syntax,
plan, ownership, and diff checks passed. The full suite used process-local Git configuration
`init.defaultBranch=master` as requested by the reviewer; no global configuration changed. The lead
separately observed live generation 2 delivery to `default:w1:p2`, Codex session
`01a0aa05-11f1-7842-8f2e-1ddd07b4091e`, at `2026-09-16T12:27:41Z`; this is lead-observed evidence,
not an engineer rerun. Round 2 must inspect only `33fca99..HEAD` and this P1 closure.

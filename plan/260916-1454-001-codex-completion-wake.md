# 260916-1454-001 — Codex completion wake without model polling

**Status:** in-progress · **Owner:** shell-engineer · **Depends on:** —
**Engine:** codex
**Validation:** strict
PR: none
**Next:** scripts/agent-spawn.sh 260916-1454-001
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

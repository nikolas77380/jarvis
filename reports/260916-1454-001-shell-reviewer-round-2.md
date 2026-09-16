# 260916-1454-001 — shell-reviewer round 2

**Verdict:** REQUEST_CHANGES
**Review round:** 2 of 2
**Reviewed range:** `33fca99..298dc02`
**Previous reviewed tip:** `33fca99`
**Reviewed HEAD:** `298dc020dd871eb3c81a6db2d61770c9f1187fa8`

## Finding

### [P1] Delivered-claim rollover is serialized but not failure-atomic

`scripts/codex-completion-watch.sh:165` moves the only canonical delivered record into the archive,
then `scripts/codex-completion-watch.sh:196-215` constructs and writes the new pending record. If the
process exits or `codex_completion_write` fails after the `mv` and before its final atomic rename,
the task has neither its prior delivered canonical record nor the promised new-generation claim.
`status` and `reconcile` then report no active watcher. The task lock prevents a concurrent writer,
but it cannot make these two filesystem transitions atomic or roll the first one back.

This leaves the round-one P1 only partially closed and contradicts the new operational contract in
`docs/codex-completion.md:27-31`, which says `start` atomically archives the delivered claim and
registers the newer one. Preserve the old canonical record until the replacement is durable, or
restore it on every failed replacement path. Add an injected-write-failure regression proving that
the old delivered claim remains canonical when new-generation registration cannot commit.

## Closure assessment

- Successful rollover is restricted to a strictly newer canonical numeric generation under the
  existing task lock.
- Same-generation duplicate and lower-generation rollback registration are rejected.
- Pending, waiting, failed, delivering, and uncertain records are not replaceable; the focused
  regression directly exercises waiting and uncertain records, and the shared non-delivered branch
  covers the remaining states.
- On successful rollover, archived generation 1 and 2 records retain their original source role,
  source agent, delivered status, and recipient session identity.
- The engineer → reviewer → fixer regression delivers exactly once for each of three generations.
- The delta does not touch `agents/orchestrator.md`, Claude wait behavior, or the universal spawn,
  switch, review, and wait scripts.

## Independent checks

- `bash tests/codex-completion.test.sh` — pass.
- `bash tests/agent-wait.test.sh`, `tests/engine-selection.test.sh`,
  `tests/quota-resume.test.sh`, and `tests/state-lock.test.sh` — pass.
- `bash tests/root-project.test.sh`, `tests/root-project-discovery.test.sh`,
  `tests/root-project-lifecycle.test.sh`, and `tests/root-project-worktree-guard.test.sh` — pass.
- `env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch
  GIT_CONFIG_VALUE_0=master bash -e -c '<fail-fast tests/*.test.sh loop>'` — pass, exit 0; all 20
  existing shell test files ran. The process-local override made `tests/observation.test.sh` pass and
  did not change global Git configuration.
- `shellcheck -e SC1091 scripts/codex-completion-lib.sh
  scripts/codex-completion-watch.sh tests/codex-completion.test.sh` — pass.
- `bash -n scripts/codex-completion-lib.sh scripts/codex-completion-watch.sh
  tests/codex-completion.test.sh` — pass.
- `scripts/plan-check.sh` — pass.
- `scripts/owns-check.sh` — pass; no overlaps among 2 active cards and 5 claims.
- `git diff --check 33fca99..298dc02` — pass.
- `git diff --quiet 33fca99..298dc02 -- agents/orchestrator.md scripts/agent-wait.sh
  scripts/agent-review.sh scripts/agent-spawn.sh scripts/agent-switch.sh` — pass.

## Material limits

- Review was limited to `33fca99..298dc02` and closure of the round-one P1; unrelated baseline
  behavior was not reopened.
- No live fleet state was mutated. The lead's observed generation-2 delivery at
  `2026-09-16T12:27:41Z` to captured Codex `default:w1:p2` was accepted as supplied evidence and was
  not repeated.
- The full suite emitted the known sandbox-only `~/.claude.json` `mktemp` diagnostics in runtime,
  role-resolution, and root-lifecycle fixtures; every affected test still exited 0.

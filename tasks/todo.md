# Harness operational reliability

- [x] Task/run locks
  - Acceptance: live contention refuses; stale ownership is recoverable; state writes serialize.
  - Verify: `tests/state-lock.test.sh`
- [x] Doctor and agent reconciliation
  - Acceptance: drift is structured; repair is conservative and explicit.
  - Verify: `tests/doctor-reconcile.test.sh`
- [x] Clean Slate reconcile and retry
  - Acceptance: partial operations resume without duplicate agent, push, or PR.
  - Verify: `tests/clean-slate-recovery.test.sh`
- [x] Safe teardown
  - Acceptance: dry by default; dirty/unpublished work refuses; eligible worktree is removed safely.
  - Verify: `tests/task-teardown.test.sh`
- [x] Fleet snapshot and session recovery view
  - Acceptance: one stable local JSON contract drives the human view.
  - Verify: `tests/fleet-snapshot.test.sh`
- [ ] Documentation and full regression suite
  - Verify: all `tests/*.test.sh` and ShellCheck pass.

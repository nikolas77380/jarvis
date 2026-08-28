# Operational reliability

The harness has one read-only observation seam. `harness-observe.sh <task-id>` combines the task
card, runtime metadata, exact Herdr endpoint, Git worktree, branch/HEAD, and Clean Slate metadata into
`harness-task-observation.v1`. `unknown` is never treated as proof that an agent stopped.

```bash
scripts/fleet-snapshot.sh --json
scripts/harness-doctor.sh --json
scripts/agent-reconcile.sh <task-id>
scripts/agent-reconcile.sh <task-id> --repair
```

Fleet snapshot is local-only and is the source for `session-start.sh`. Doctor is read-only and exits
nonzero when any observation contains issues. Reconcile is also read-only unless `--repair` is
explicit; its only current repair marks runtime stopped when Herdr successfully confirms that the
exact recorded agent does not exist. Transport failure remains `unknown` and is not repaired.

All task state mutations use the portable lock in `harness-state-lib.sh`. A live lock owner is never
displaced. On Linux and unrestricted macOS the process start identity protects against PID reuse;
restricted hosts fall back to PID liveness and fail conservatively.

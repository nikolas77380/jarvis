# Harness operational reliability — specification and plan

## Objective

Make task state recoverable and safe under concurrent commands, missing Herdr endpoints, partial
Clean Slate operations, and cleanup. Every conclusion must be derivable from local durable state;
network enrichment is outside this package.

## Public commands

```text
scripts/harness-doctor.sh [--json]
scripts/agent-reconcile.sh <task-id> [--repair]
scripts/clean-slate-protocol.sh reconcile <task-id>
scripts/clean-slate-protocol.sh retry <task-id>
scripts/task-teardown.sh <task-id> [--execute]
scripts/fleet-snapshot.sh [--json]
```

## Interfaces and invariants

- A task-scoped portable `mkdir` lock serializes every runtime or pipeline state mutation.
- Lock ownership records PID and process identity where the host exposes it, with PID-liveness as
  the restricted-host fallback. A live foreign owner is never displaced.
- Doctor is read-only and exits nonzero for malformed metadata, missing worktrees, runtime drift, or
  pipeline drift. `--json` emits `harness-doctor.v1`.
- Reconcile reports observed versus recorded state. `--repair` may only mark a provably missing
  endpoint stopped; it never recreates an agent or changes Git history.
- Clean Slate reconcile detects completed result files, existing PR identity, and CI state without
  repeating mutations. Retry is allowed only from a failed deterministic check, publishing, or CI
  observation; review/fixer failures require an explicit response.
- Teardown defaults to a read-only refusal/eligibility report. `--execute` closes known Herdr tabs,
  removes a clean worktree only when its branch is fully published or has a terminal PR outcome,
  archives metadata, and never deletes the branch.
- Fleet snapshot is the single local JSON projection for task, agent, worktree, branch, Clean Slate,
  and next-action state. Human views consume this interface.

## Project structure and style

- Shared locking and observation helpers: `scripts/harness-state-lib.sh`.
- Commands: `scripts/*.sh`; shell is Bash 3-compatible and uses no `eval`.
- Tests: isolated shell integration tests with fake Herdr/GitHub adapters.
- Documentation: `docs/operational-reliability.md`.

## Testing strategy

Each slice begins with a failing shell test. Tests cover live-lock refusal, stale-lock recovery,
read-only doctor behavior, conservative reconciliation, teardown refusal/success, retry
idempotence, and stable fleet JSON. Existing runtime and Clean Slate suites must remain green.

## Boundaries

- Always: atomic writes, exact recorded identities, fail closed on ambiguity, preserve branches.
- Ask first: deleting unpushed commits, force-closing an unverified endpoint, network repair.
- Never: merge, reset, force-push, delete a dirty worktree, infer success from terminal prose.

## Implementation order

1. Portable task locks and concurrent mutation tests.
2. Structured local observations, doctor, and conservative agent reconciliation.
3. Clean Slate reconcile/retry.
4. Teardown eligibility and explicit execution.
5. Fleet snapshot, session-start integration, documentation, complete verification.

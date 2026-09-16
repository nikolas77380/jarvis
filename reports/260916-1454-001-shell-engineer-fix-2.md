# 260916-1454-001 — shell-engineer targeted fix after review round 2

## Result

Closed the round-two P1 at baseline `298dc02`. Delivered-claim rollover no longer removes the old
canonical record before the newer claim is durable. This is a targeted fix for PR #7, not a third
full review.

## Implementation

- `archive_delivered_claim` writes a copy to a temporary archive file and renames it into place while
  the old delivered record remains canonical.
- The existing `atomic_meta_write` remains the commit point for the newer canonical claim.
- An archive left by a failed replacement attempt is reused only when `cmp` proves it is byte-for-byte
  identical to the old canonical record. A malformed or differing archive fails closed and is never
  overwritten.
- Archive-write and replacement-write failures release the task lock, preserve the prior canonical
  state, and stop before `run_claim`, so no prompt is sent.
- Source/recipient identity, task locking, generation ordering, duplicate rejection, and delivery
  semantics are unchanged.

## TDD evidence

The focused regression failed before the implementation with exit 2 after injected canonical rename
failure removed the canonical file. After the fix, `bash tests/codex-completion.test.sh` passes and
proves:

- injected replacement rename failure leaves the old delivered canonical file readable and
  byte-identical, sends no prompt, and permits a successful retry;
- that retry idempotently reuses the matching archive created by the failed attempt;
- injected archive rename failure leaves the old delivered canonical file readable and
  byte-identical, sends no prompt, and permits a successful retry;
- an unrelated archive at the rollover path is preserved byte-identically and blocks replacement.

## Verification

- `bash tests/codex-completion.test.sh` — pass.
- Process-local `init.defaultBranch=master` focused compatibility run covering agent-wait,
  engine-selection, quota-resume, state-lock, and all root-project tests — pass.
- Process-local `init.defaultBranch=master` fail-fast run of every existing `tests/*.test.sh` — pass.
  The known sandbox-only `~/.claude.json` `mktemp` diagnostics appeared; affected tests exited 0.
- `shellcheck -e SC1091 scripts/codex-completion-lib.sh scripts/codex-completion-watch.sh
  tests/codex-completion.test.sh` — pass.
- `bash -n scripts/codex-completion-lib.sh scripts/codex-completion-watch.sh
  tests/codex-completion.test.sh` — pass.
- `scripts/plan-check.sh` — pass.
- `scripts/owns-check.sh` — pass; no overlapping claims among 2 active cards and 5 claims.

## Documentation and live evidence

`docs/codex-completion.md` now states the measured failure guarantee and archive conflict behavior.
The lead observed fixed-generation live delivery at `2026-09-16T12:50:35Z` to `default:w1:p2`:
source generation 5, status `delivered`, attempt 1. This is lead-supplied live evidence, not an
engineer rerun.

## Next gate

Targeted independent verification should inspect only this fix hunk and reproduce the injected
archive/replacement failure paths. It is not another complete review.

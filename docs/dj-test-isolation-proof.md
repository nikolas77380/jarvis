# Jarvis test isolation proof

This record is the concurrent isolation proof for the portable parallel candidate set.
`bin/dj-test-isolation-proof.sh` is the authoritative harness and `docs/dj-test-isolation-proof.json` is the machine-readable result.
`bin/dj-test-run.sh` owns the production lane partition.

## Verification

- Date: 2026-08-20
- Command: `bin/dj-test-isolation-proof.sh --jobs 4 --json /tmp/dj-isolation-proof.json`
- Result: `DJ_ISOLATION_SUMMARY total=24 failed=0 concurrency=4 duration_ms=113278`

| Field | Value |
|---|---|
| `run_id` | `dj-isolation-1787273044622-10250` |
| `started_at` | `2026-08-21T00:44:04Z` |
| `finished_at` | `2026-08-21T00:45:57Z` |
| concurrency | 4 |
| candidates | 24 |
| failed | 0 |
| wall duration | 113278 ms |

## Candidate set

- `tests/dj-arm-pretool-check.test.sh`
- `tests/dj-backend-herdr.test.sh`
- `tests/dj-brief.test.sh`
- `tests/dj-captain-hold-lifecycle.test.sh`
- `tests/dj-cd-pretool-check.test.sh`
- `tests/dj-composer-ghost.test.sh`
- `tests/dj-composer-lib.test.sh`
- `tests/dj-crew-state.test.sh`
- `tests/dj-ensure-agents-md.test.sh`
- `tests/dj-grok-harness.test.sh`
- `tests/dj-herdr-lab.test.sh`
- `tests/dj-lint.test.sh`
- `tests/dj-pi-primary-types.test.sh`
- `tests/dj-pr-merge.test.sh`
- `tests/dj-review-diff.test.sh`
- `tests/dj-send-popup-settle.test.sh`
- `tests/dj-send-settle.test.sh`
- `tests/dj-send-strict.test.sh`
- `tests/dj-spawn-batch.test.sh`
- `tests/dj-supervision-instructions.test.sh`
- `tests/dj-test-run.test.sh`
- `tests/dj-tmux-submit-busy.test.sh`
- `tests/dj-transition-lib.test.sh`
- `tests/dj-x-mode.test.sh`

## Durations

| duration_ms | exit | worker | script |
|---:|---:|---:|---|
| 45356 | 0 | 2 | `tests/dj-backend-herdr.test.sh` |
| 35415 | 0 | 24 | `tests/dj-x-mode.test.sh` |
| 35095 | 0 | 4 | `tests/dj-captain-hold-lifecycle.test.sh` |
| 27529 | 0 | 1 | `tests/dj-arm-pretool-check.test.sh` |
| 20922 | 0 | 21 | `tests/dj-test-run.test.sh` |
| 17558 | 0 | 8 | `tests/dj-crew-state.test.sh` |
| 16582 | 0 | 5 | `tests/dj-cd-pretool-check.test.sh` |
| 9766 | 0 | 12 | `tests/dj-lint.test.sh` |
| 9562 | 0 | 11 | `tests/dj-herdr-lab.test.sh` |
| 6768 | 0 | 10 | `tests/dj-grok-harness.test.sh` |
| 6290 | 0 | 14 | `tests/dj-pr-merge.test.sh` |
| 5569 | 0 | 6 | `tests/dj-composer-ghost.test.sh` |
| 4563 | 0 | 16 | `tests/dj-send-popup-settle.test.sh` |
| 4021 | 0 | 22 | `tests/dj-tmux-submit-busy.test.sh` |
| 3544 | 0 | 7 | `tests/dj-composer-lib.test.sh` |
| 3025 | 0 | 18 | `tests/dj-send-strict.test.sh` |
| 2753 | 0 | 17 | `tests/dj-send-settle.test.sh` |
| 2166 | 0 | 15 | `tests/dj-review-diff.test.sh` |
| 1315 | 0 | 3 | `tests/dj-brief.test.sh` |
| 975 | 0 | 19 | `tests/dj-spawn-batch.test.sh` |
| 598 | 0 | 13 | `tests/dj-pi-primary-types.test.sh` |
| 513 | 0 | 9 | `tests/dj-ensure-agents-md.test.sh` |
| 331 | 0 | 20 | `tests/dj-supervision-instructions.test.sh` |
| 99 | 0 | 23 | `tests/dj-transition-lib.test.sh` |

## Scope

Each worker used a separate mode-`0700` temporary root and private `TMPDIR` and `TMP`.
The harness cleared ambient `DJ_HOME` and `DJ_*_OVERRIDE` values for every worker and verified that global Git configuration was unchanged.
A candidate failure fails the aggregate run and requires investigation rather than a retry.

## Re-run

```sh
bin/dj-test-isolation-proof.sh --list
bin/dj-test-isolation-proof.sh --jobs 4 --json /tmp/dj-isolation-proof.json
bin/dj-test-run.sh --check-coverage
```

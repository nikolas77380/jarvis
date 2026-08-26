#!/usr/bin/env bash
# dj-test-run.sh - single owner of Jarvis's behavior-test runner, lane
# composition for portable CI shards, local --jobs for the proven-isolated set,
# timing markers, and the complete-regression coverage guard.
#
# Selection modes (exactly one of: --all, --family, --changed, --lane,
# --proven-isolated, or script paths):
#   dj-test-run.sh --all
#   dj-test-run.sh --family <name>
#   dj-test-run.sh --changed [--base <git-ref>]
#   dj-test-run.sh --lane portable-parallel-1|portable-parallel-2|portable-serial
#   dj-test-run.sh --lane portable-serial-<k>of<n>   (one CI serial shard)
#   dj-test-run.sh --proven-isolated
#   dj-test-run.sh tests/<name>.test.sh [more scripts...]
#
# Inspection (no execution):
#   dj-test-run.sh --list --all
#   dj-test-run.sh --list --family <name>
#   dj-test-run.sh --list --lane portable-parallel-1
#   dj-test-run.sh --list-families
#   dj-test-run.sh --list-lanes
#   dj-test-run.sh --check-coverage
#
# Aggregation (no suite execution):
#   dj-test-run.sh --aggregate-json <out.json> <lane.json> [more lane.json...]
#
# Options:
#   --json <path>   write a deterministic timing artifact after the run
#   --list          print selected script paths (one per line) and exit 0
#   --base <ref>    with --changed, compare against this ref (default: origin/main)
#   --exclude-family <name>
#                   drop scripts whose primary family matches <name> after selection
#                   (repeatable; portable CI lanes exclude real-herdr-gated so the
#                   dedicated required Herdr lane owns that coverage)
#   --fail-on-gate-skip <token>
#                   after each script, fail the run if any output line contains
#                   "skip: <token>" (e.g. --fail-on-gate-skip 'herdr not found').
#                   The required Herdr CI lane uses this so a missing pin cannot
#                   silently pass as a gate skip.
#   --jobs N        run the selected scripts with up to N concurrent workers.
#                   Default is 1 (serial). N>1 is allowed only when every
#                   selected script is in the proven-isolated set
#                   (bin/dj-test-isolation-proof.sh --list). Cap is 8. Stateful
#                   families never schedule under --jobs.
#   -h, --help      print this header
#
# Per-script machine-parseable markers (stdout):
#   DJ_TEST_BEGIN <iso8601> <script> family=<family> expected_gate_skip=<class>
#   DJ_TEST_END <iso8601> <script> exit=<code> duration_ms=<n> gate_skip=<true|false>
#
# After all scripts (stdout):
#   DJ_TEST_SUMMARY total=<n> failed=<n> skipped_gate=<n> duration_ms=<n>
#   DJ_TEST_SUMMARY_FAMILY family=<name> count=<n> duration_ms=<n> failed=<n>
#   DJ_TEST_SLOWEST rank=<k> script=<path> duration_ms=<n>
#
# Exit status is non-zero if any selected script exits non-zero or a configured
# --fail-on-gate-skip token appears. Other gate skips (first meaningful line
# matching ^skip:) remain successful and are counted as skipped_gate.
#
# Family labels, the changed-file map, and production portable-shard composition
# live in this script only (one owner). The proven-isolated candidate set remains
# owned by bin/dj-test-isolation-proof.sh; portable parallel shards are a
# duration-balanced partition of that exact set (see docs/dj-test-portable-shards.md).
#
# portable-serial stays strictly serial. Its CI shards (portable-serial-<k>of<n>)
# split it across separate runners, so two of its stateful scripts still never
# share a machine. This script owns <n>: a lane whose <n> disagrees with the
# configured shard count is refused, so a CI matrix cannot silently drop a shard.
# --changed is conservative: it over-selects related families rather than
# under-selecting, and never expands to the complete suite unless --all.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

MODE=
LIST_ONLY=0
LIST_FAMILIES=0
LIST_LANES=0
CHECK_COVERAGE=0
AGGREGATE_OUT=
FAMILY=
LANE=
BASE_REF=origin/main
JSON_PATH=
SCRIPTS=()
EXCLUDE_FAMILIES=()
FAIL_ON_GATE_SKIP=
JOBS=1
JOBS_MAX=8

# How many separate-runner shards the portable serial remainder splits into.
# One owner: CI lane names carry this count and are refused when they disagree.
PORTABLE_SERIAL_SHARDS=4

# Balance hint for a portable-serial script with no measured duration, close to
# the measured per-script mean so a newly added test neither starves nor
# overloads the shard it lands in.
PORTABLE_SERIAL_DEFAULT_WEIGHT_MS=20000

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0" >&2
}

die() {
  printf 'dj-test-run: %s\n' "$*" >&2
  exit 2
}

log() {
  printf 'dj-test-run: %s\n' "$*" >&2
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time() * 1000))'
  else
    # Second precision only when python3 is unavailable.
    echo $(($(date +%s) * 1000))
  fi
}

# Primary family for one tests/*.test.sh basename. Unmapped scripts are
# unclassified so new tests are still runnable and visible in summaries.
family_for_basename() {
  case "$1" in
    dj-arm-pretool-check.test.sh|dj-ask-user-authority.test.sh|\
    dj-bearings-board.test.sh|\
    dj-brief.test.sh|dj-vendor-auth-probe.test.sh|\
    dj-calm-pi-extension.test.sh|dj-cd-pretool-check.test.sh|\
    dj-classify-decision-key.test.sh|\
    dj-composer-ghost.test.sh|dj-composer-lib.test.sh|\
    dj-crew-state.test.sh|dj-captain-hold-lifecycle.test.sh|\
    dj-documentation-audiences.test.sh|dj-ensure-agents-md.test.sh|dj-grok-harness.test.sh|\
    dj-kimi-harness.test.sh|dj-muse-harness.test.sh|dj-herdr-lab.test.sh|dj-lint.test.sh|\
    dj-lint-workflows.test.sh|\
    dj-operational-input.test.sh|dj-pi-primary-types.test.sh|\
    dj-send-popup-settle.test.sh|dj-send-settle.test.sh|\
    dj-subagent-pretool-check.test.sh|\
    dj-supervision-instructions.test.sh|dj-task-delivery.test.sh|\
    dj-tmux-submit-busy.test.sh|dj-trace-context-lib.test.sh|\
    dj-transition-lib.test.sh|\
    dj-test-run.test.sh|dj-test-isolation-proof.test.sh)
      printf '%s\n' pure-contract-unit
      ;;
    dj-daemon.test.sh|dj-guard-stale-banner.test.sh|dj-pi-watch-extension.test.sh|\
    dj-session-lock-ancestry.test.sh|dj-cursor-primary.test.sh|\
    dj-supervision-events.test.sh|dj-turnend-guard.test.sh|dj-wake-daemon-lifecycle-e2e.test.sh|\
    dj-wake-drain-unread-status.test.sh|\
    dj-tool-update-check.test.sh|\
    dj-wake-queue.test.sh|dj-watch-arm.test.sh|dj-watch-checkpoint.test.sh|dj-watch-recovery-loop.test.sh|\
    dj-watch-triage.test.sh|dj-task-inbox.test.sh|\
    dj-watcher-lock.test.sh|dj-inactive-reconcile.test.sh)
      printf '%s\n' watcher-wake-lock
      ;;
    dj-afk-inject-herdr-e2e.test.sh|dj-afk-launch.test.sh|dj-backend-autodetect-smoke.test.sh|\
    dj-backend-herdr-eventwait-smoke.test.sh|dj-backend-herdr-presentation-e2e.test.sh|\
    dj-backend-herdr-launcher-workspace-e2e.test.sh|\
    dj-backend-herdr-prune-safety-e2e.test.sh|dj-backend-herdr-respawn-idem-e2e.test.sh|\
    dj-herdr-session-cleanup-e2e.test.sh|\
    dj-backend-herdr-smoke.test.sh|dj-backend-herdr-workspace-per-home-e2e.test.sh|\
    dj-control-herdr-smoke.test.sh)
      printf '%s\n' real-herdr-gated
      ;;
    dj-backlog-handoff.test.sh|dj-on.test.sh|dj-remote-backlog-handoff.test.sh|\
    dj-remote-doctor.test.sh|dj-remote-job.test.sh|dj-remote-job-orphan-reap.test.sh|\
    dj-remote-reply.test.sh|dj-remote-secondmate-lifecycle-e2e.test.sh|\
    dj-remote-secondmate-trace-context.test.sh|\
    dj-secondmate-harness.test.sh|dj-secondmate-lifecycle-e2e.test.sh|\
    dj-secondmate-liveness.test.sh|dj-secondmate-safety.test.sh|dj-secondmate-sync.test.sh|\
    dj-startup-memory-budget.test.sh|dj-stow-cascade.test.sh|\
    dj-send-secondmate-marker.test.sh|dj-shared-captain-inheritance.test.sh)
      printf '%s\n' secondmate
      ;;
    dj-bootstrap.test.sh|dj-bootstrap-network-parallel.test.sh|dj-fleet-sync.test.sh|dj-gate-refuse.test.sh|dj-gotmp.test.sh|\
    dj-session-start.test.sh|dj-sessionstart-nudge.test.sh|dj-startup-network.test.sh|\
    dj-tangle-guard.test.sh|dj-update.test.sh)
      printf '%s\n' session-bootstrap
      ;;
    dj-afk-pi-herdr-return-e2e.test.sh|\
    dj-cmux-claude-composer-live-e2e.test.sh|\
    dj-composer-matrix-live-e2e.test.sh|\
    dj-codex-continuity-live-e2e.test.sh|dj-grok-continuity-live-e2e.test.sh|\
    dj-cursor-primary-live-e2e.test.sh|\
    dj-grok-stop-live-e2e.test.sh|dj-harness-liveness-drift-live-e2e.test.sh|\
    dj-muse-signals-live-e2e.test.sh|\
    dj-herdr-version-floor-live-e2e.test.sh|\
    dj-opencode-primary-live-e2e.test.sh|dj-pi-branch-live-e2e.test.sh|\
    dj-pi-primary-live-e2e.test.sh|\
    dj-sessionstart-hook-live-e2e.test.sh|dj-sessionstart-instruction-refresh-live-e2e.test.sh|\
    dj-quota-array-dispatch-live-e2e.test.sh|dj-send-secondmate-marker-herdr-e2e.test.sh|\
    dj-send-inbox-doorbell-live-e2e.test.sh|\
    dj-herdr-submit-confirm-live-e2e.test.sh)
      printf '%s\n' live-harness-optin
      ;;
    dj-backend-herdr.test.sh|dj-backend-tmux-smoke.test.sh|dj-backend.test.sh|\
    dj-tmux-agent-liveness.test.sh|\
    dj-control.test.sh|dj-control-relaunch.test.sh|\
    dj-herdr-session-cleanup.test.sh|dj-send-resolve-key.test.sh|dj-send-strict.test.sh|\
    dj-send-inbox.test.sh|dj-spawn-batch.test.sh|\
    dj-spawn-dispatch-profile.test.sh|\
    dj-trace-context-spawn.test.sh|dj-spawn-worktree-settle.test.sh|\
    dj-teardown-endpoint-safety.test.sh)
      printf '%s\n' backend-dispatch
      ;;
    dj-pr-check-security.test.sh|dj-pr-merge.test.sh|dj-review-diff.test.sh|\
    dj-teardown.test.sh|dj-x-mode.test.sh)
      printf '%s\n' pr-forge
      ;;
    dj-afk-inject-e2e.test.sh|dj-afk-return.test.sh)
      printf '%s\n' afk
      ;;
    dj-bearings-snapshot.test.sh|dj-fleet-snapshot-view.test.sh)
      printf '%s\n' snapshot-bearings
      ;;
    dj-backend-cmux.test.sh|dj-backend-cmux-smoke.test.sh)
      printf '%s\n' cmux
      ;;
    dj-backend-zellij.test.sh|dj-backend-zellij-smoke.test.sh)
      printf '%s\n' zellij
      ;;
    dj-backend-orca.test.sh)
      printf '%s\n' orca
      ;;
    *)
      printf '%s\n' unclassified
      ;;
  esac
}

expected_gate_skip_for_family() {
  case "$1" in
    real-herdr-gated) printf '%s\n' herdr ;;
    live-harness-optin) printf '%s\n' optin-env ;;
    cmux|zellij|orca) printf '%s\n' optional-binary ;;
    snapshot-bearings) printf '%s\n' optional-binary ;;
    *) printf '%s\n' none ;;
  esac
}

list_known_families() {
  cat <<'EOF'
pure-contract-unit
watcher-wake-lock
real-herdr-gated
secondmate
session-bootstrap
live-harness-optin
backend-dispatch
pr-forge
afk
snapshot-bearings
cmux
zellij
orca
unclassified
EOF
}

list_known_lanes() {
  local i
  printf '%s\n' portable-parallel-1
  printf '%s\n' portable-parallel-2
  printf '%s\n' portable-serial
  i=1
  while [ "$i" -le "$PORTABLE_SERIAL_SHARDS" ]; do
    printf 'portable-serial-%sof%s\n' "$i" "$PORTABLE_SERIAL_SHARDS"
    i=$((i + 1))
  done
  printf '%s\n' real-herdr-gated
}

# Exact proven-isolated candidate set (same paths as
# bin/dj-test-isolation-proof.sh --list). Do not expand without a new concurrent
# isolation proof archive.
list_proven_isolated() {
  cat <<'EOF'
tests/dj-arm-pretool-check.test.sh
tests/dj-backend-herdr.test.sh
tests/dj-brief.test.sh
tests/dj-captain-hold-lifecycle.test.sh
tests/dj-cd-pretool-check.test.sh
tests/dj-composer-ghost.test.sh
tests/dj-composer-lib.test.sh
tests/dj-crew-state.test.sh
tests/dj-ensure-agents-md.test.sh
tests/dj-grok-harness.test.sh
tests/dj-herdr-lab.test.sh
tests/dj-lint.test.sh
tests/dj-pi-primary-types.test.sh
tests/dj-pr-merge.test.sh
tests/dj-review-diff.test.sh
tests/dj-send-popup-settle.test.sh
tests/dj-send-settle.test.sh
tests/dj-send-strict.test.sh
tests/dj-spawn-batch.test.sh
tests/dj-supervision-instructions.test.sh
tests/dj-test-run.test.sh
tests/dj-tmux-submit-busy.test.sh
tests/dj-transition-lib.test.sh
tests/dj-x-mode.test.sh
EOF
}

# Portable parallel shard 1: LPT balance of the proven-isolated set using the
# current concurrent-proof durations in docs/dj-test-isolation-proof.json.
# Execution order is longest first so wall-clock stays near the balanced sum.
list_portable_parallel_1() {
  cat <<'EOF'
tests/dj-x-mode.test.sh
tests/dj-cd-pretool-check.test.sh
tests/dj-captain-hold-lifecycle.test.sh
tests/dj-test-run.test.sh
tests/dj-composer-ghost.test.sh
tests/dj-grok-harness.test.sh
tests/dj-lint.test.sh
tests/dj-pi-primary-types.test.sh
tests/dj-review-diff.test.sh
tests/dj-brief.test.sh
tests/dj-transition-lib.test.sh
EOF
}

# Portable parallel shard 2: the complementary LPT half of the proven set.
list_portable_parallel_2() {
  cat <<'EOF'
tests/dj-backend-herdr.test.sh
tests/dj-arm-pretool-check.test.sh
tests/dj-crew-state.test.sh
tests/dj-herdr-lab.test.sh
tests/dj-pr-merge.test.sh
tests/dj-send-popup-settle.test.sh
tests/dj-tmux-submit-busy.test.sh
tests/dj-send-settle.test.sh
tests/dj-send-strict.test.sh
tests/dj-spawn-batch.test.sh
tests/dj-supervision-instructions.test.sh
tests/dj-ensure-agents-md.test.sh
tests/dj-composer-lib.test.sh
EOF
}

is_proven_isolated_script() {
  local want=$1 line
  while IFS= read -r line; do
    [ "$line" = "$want" ] && return 0
  done < <(list_proven_isolated)
  return 1
}

# The portable serial remainder: every tests/*.test.sh that is neither
# proven-isolated nor real-herdr-gated. Watcher, lock, AFK, real tmux, daemon,
# secondmate lifecycle, bootstrap, live-harness opt-in, GUI-backend, and other
# unproven work stays here. Derived rather than enumerated so a newly added test
# lands here by default instead of falling out of every lane.
list_portable_serial() {
  local s base fam
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    base=$(basename "$s")
    fam=$(family_for_basename "$base")
    if [ "$fam" = "real-herdr-gated" ]; then
      continue
    fi
    if is_proven_isolated_script "$s"; then
      continue
    fi
    printf '%s\n' "$s"
  done < <(all_repo_tests)
}

# Measured portable-serial script durations in milliseconds, from the CI timing
# artifact recorded in docs/dj-test-portable-shards.md. These are balance hints
# only: the shard partition stays complete and disjoint whatever they say, so a
# stale hint costs balance rather than coverage. That doc owns the refresh
# procedure.
portable_serial_weight_hints() {
  cat <<'EOF'
tests/dj-afk-inject-e2e.test.sh 35900
tests/dj-afk-pi-herdr-return-e2e.test.sh 66
tests/dj-afk-return.test.sh 3974
tests/dj-ask-user-authority.test.sh 83
tests/dj-backend-cmux-smoke.test.sh 30
tests/dj-backend-cmux.test.sh 3351
tests/dj-backend-herdr-focus-flash-e2e.test.sh 21
tests/dj-backend-orca.test.sh 14681
tests/dj-backend-tmux-smoke.test.sh 361
tests/dj-backend-zellij-smoke.test.sh 22
tests/dj-backend-zellij.test.sh 8297
tests/dj-backend.test.sh 17169
tests/dj-backlog-handoff.test.sh 4157
tests/dj-bearings-board.test.sh 3385
tests/dj-bearings-snapshot.test.sh 68659
tests/dj-bootstrap-network-parallel.test.sh 8000
tests/dj-bootstrap.test.sh 38417
tests/dj-busy-adapter-wiring.test.sh 14880
tests/dj-busy-state.test.sh 714
tests/dj-calm-pi-extension.test.sh 464
tests/dj-classify-decision-key.test.sh 928
tests/dj-claude-stop-autoarm-live-e2e.test.sh 30
tests/dj-claude-stop-autoarm.test.sh 60633
tests/dj-cmux-claude-composer-live-e2e.test.sh 20
tests/dj-codex-continuity-live-e2e.test.sh 19
tests/dj-composer-matrix-live-e2e.test.sh 21
tests/dj-control-relaunch.test.sh 31881
tests/dj-control.test.sh 36712
tests/dj-cursor-harness.test.sh 30071
tests/dj-cursor-primary-live-e2e.test.sh 20
tests/dj-cursor-primary.test.sh 52324
tests/dj-daemon.test.sh 25834
tests/dj-documentation-audiences.test.sh 642
tests/dj-fleet-snapshot-view.test.sh 6995
tests/dj-fleet-sync.test.sh 20194
tests/dj-gate-refuse.test.sh 4071
tests/dj-gitignore-config.test.sh 63
tests/dj-gotmp.test.sh 762
tests/dj-grok-continuity-live-e2e.test.sh 19
tests/dj-grok-stop-live-e2e.test.sh 21
tests/dj-guard-stale-banner.test.sh 11280
tests/dj-harness-liveness-drift-live-e2e.test.sh 19
tests/dj-herdr-session-cleanup.test.sh 14120
tests/dj-herdr-submit-confirm-live-e2e.test.sh 20
tests/dj-herdr-version-floor-live-e2e.test.sh 20
tests/dj-inactive-reconcile.test.sh 41671
tests/dj-kimi-harness.test.sh 15092
tests/dj-lint-workflows.test.sh 744
tests/dj-muse-harness.test.sh 27414
tests/dj-muse-signals-live-e2e.test.sh 21
tests/dj-on.test.sh 8602
tests/dj-opencode-primary-live-e2e.test.sh 22
tests/dj-operational-input.test.sh 246
tests/dj-peek-remote.test.sh 848
tests/dj-pending-reply.test.sh 19488
tests/dj-pi-primary-live-e2e.test.sh 41
tests/dj-pi-watch-extension.test.sh 17979
tests/dj-pr-check-security.test.sh 250417
tests/dj-procevent-when.test.sh 15249
tests/dj-procevent.test.sh 53142
tests/dj-project-origin.test.sh 105
tests/dj-public-followup.test.sh 36301
tests/dj-quota-array-dispatch-live-e2e.test.sh 18
tests/dj-remote-backlog-handoff.test.sh 20389
tests/dj-remote-doctor.test.sh 4705
tests/dj-remote-entrypoint.test.sh 98
tests/dj-remote-job-orphan-reap.test.sh 2903
tests/dj-remote-job.test.sh 48068
tests/dj-remote-reply.test.sh 40906
tests/dj-remote-secondmate-lifecycle-e2e.test.sh 170240
tests/dj-remote-secondmate-parent-binding.test.sh 13064
tests/dj-remote-secondmate-trace-context.test.sh 39927
tests/dj-secondmate-harness.test.sh 123471
tests/dj-secondmate-lifecycle-e2e.test.sh 6539
tests/dj-secondmate-liveness.test.sh 16365
tests/dj-secondmate-safety.test.sh 49011
tests/dj-secondmate-sync.test.sh 29236
tests/dj-send-remote-delivery.test.sh 4892
tests/dj-send-resolve-key.test.sh 13450
tests/dj-send-secondmate-marker-herdr-e2e.test.sh 45
tests/dj-send-secondmate-marker.test.sh 4439
tests/dj-session-lock-ancestry.test.sh 1205
tests/dj-session-start.test.sh 144836
tests/dj-sessionstart-hook-live-e2e.test.sh 21
tests/dj-sessionstart-instruction-refresh-live-e2e.test.sh 21
tests/dj-sessionstart-nudge.test.sh 26684
tests/dj-shared-captain-inheritance.test.sh 10672
tests/dj-spawn-dispatch-profile.test.sh 57765
tests/dj-spawn-pool-base-freshen.test.sh 13257
tests/dj-spawn-worktree-settle.test.sh 4828
tests/dj-startup-memory-budget.test.sh 6550
tests/dj-startup-network.test.sh 48888
tests/dj-stow-cascade.test.sh 2986
tests/dj-subagent-pretool-check.test.sh 1066
tests/dj-supervision-events.test.sh 1431
tests/dj-tangle-guard.test.sh 8364
tests/dj-task-delivery.test.sh 2414
tests/dj-teardown-endpoint-safety.test.sh 7295
tests/dj-teardown.test.sh 87400
tests/dj-test-fixture-cleanup.test.sh 532
tests/dj-test-isolation-proof.test.sh 451
tests/dj-tmux-agent-liveness.test.sh 4065
tests/dj-tool-update-check.test.sh 12846
tests/dj-trace-context-lib.test.sh 194
tests/dj-trace-context-spawn.test.sh 35325
tests/dj-turnend-guard.test.sh 34915
tests/dj-update.test.sh 5280
tests/dj-vendor-auth-probe.test.sh 43243
tests/dj-wake-daemon-lifecycle-e2e.test.sh 6219
tests/dj-wake-drain-open-decisions-cursor.test.sh 17357
tests/dj-wake-drain-open-decisions.test.sh 11300
tests/dj-wake-drain-unread-status.test.sh 25214
tests/dj-wake-queue.test.sh 30887
tests/dj-watch-arm.test.sh 53598
tests/dj-watch-checkpoint.test.sh 5293
tests/dj-watch-recovery-loop.test.sh 58721
tests/dj-watch-triage.test.sh 142409
tests/dj-watcher-lock.test.sh 54364
EOF
}

portable_serial_weight_for() {
  local want=$1 path ms
  while read -r path ms; do
    if [ "$path" = "$want" ]; then
      printf '%s\n' "$ms"
      return 0
    fi
  done < <(portable_serial_weight_hints)
  printf '%s\n' "$PORTABLE_SERIAL_DEFAULT_WEIGHT_MS"
}

# Longest-processing-time assignment of the serial remainder to
# PORTABLE_SERIAL_SHARDS bins, printing "<shard>\t<script>" for every script.
# Deterministic: candidates are ordered by hint descending then path, and ties
# between equally loaded bins always take the lowest bin index.
portable_serial_assignments() {
  local ms script i best best_load
  local -a loads=()
  i=1
  while [ "$i" -le "$PORTABLE_SERIAL_SHARDS" ]; do
    loads[i]=0
    i=$((i + 1))
  done
  while IFS=$'\t' read -r ms script; do
    [ -n "$script" ] || continue
    best=1
    best_load=${loads[1]}
    i=2
    while [ "$i" -le "$PORTABLE_SERIAL_SHARDS" ]; do
      if [ "${loads[i]}" -lt "$best_load" ]; then
        best_load=${loads[i]}
        best=$i
      fi
      i=$((i + 1))
    done
    loads[best]=$((best_load + ms))
    printf '%s\t%s\n' "$best" "$script"
  done < <(
    while IFS= read -r script; do
      [ -n "$script" ] || continue
      printf '%s\t%s\n' "$(portable_serial_weight_for "$script")" "$script"
    done < <(list_portable_serial) | LC_ALL=C sort -t$'\t' -k1,1nr -k2,2
  )
}

# Parse "<k>of<n>" from a portable-serial shard lane and echo <k>, refusing when
# <n> disagrees with this script's configured count so a CI matrix built for a
# different shard count fails loudly instead of dropping tests.
portable_serial_shard_index() {
  local lane=$1 spec index count
  spec=${lane#portable-serial-}
  index=${spec%%of*}
  count=${spec#*of}
  case "$spec" in
    *of*) ;;
    *) die "unknown lane '$lane' (see --list-lanes)" ;;
  esac
  case "$index" in
    ''|*[!0-9]*) die "unknown lane '$lane' (see --list-lanes)" ;;
  esac
  case "$count" in
    ''|*[!0-9]*) die "unknown lane '$lane' (see --list-lanes)" ;;
  esac
  if [ "$count" -ne "$PORTABLE_SERIAL_SHARDS" ]; then
    die "lane '$lane' asks for $count portable serial shards but this runner is configured for $PORTABLE_SERIAL_SHARDS (see --list-lanes)"
  fi
  if [ "$index" -lt 1 ] || [ "$index" -gt "$PORTABLE_SERIAL_SHARDS" ]; then
    die "lane '$lane' shard index is outside 1..$PORTABLE_SERIAL_SHARDS (see --list-lanes)"
  fi
  printf '%s\n' "$index"
}

select_proven_isolated() {
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    add_script "$s"
  done < <(list_proven_isolated)
}

select_lane() {
  local want=$1 s shard idx found=0
  case "$want" in
    portable-parallel-1)
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        add_script "$s"
        found=1
      done < <(list_portable_parallel_1)
      ;;
    portable-parallel-2)
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        add_script "$s"
        found=1
      done < <(list_portable_parallel_2)
      ;;
    portable-serial)
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        add_script "$s"
        found=1
      done < <(list_portable_serial)
      ;;
    portable-serial-*)
      # One separate-runner shard of the same remainder, still serial in itself.
      shard=$(portable_serial_shard_index "$want")
      while IFS=$'\t' read -r idx s; do
        [ -n "$s" ] || continue
        if [ "$idx" = "$shard" ]; then
          add_script "$s"
          found=1
        fi
      done < <(portable_serial_assignments)
      ;;
    real-herdr-gated)
      select_family real-herdr-gated
      found=1
      ;;
    *)
      die "unknown lane '$want' (see --list-lanes)"
      ;;
  esac
  [ "$found" -eq 1 ] || die "lane '$want' selected no tests"
}

run_coverage_guard() {
  local tmp missing extra a b shard
  local -a saved_scripts=()
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dj-test-coverage.XXXXXX")

  all_repo_tests | LC_ALL=C sort -u >"$tmp/all"
  list_proven_isolated | LC_ALL=C sort -u >"$tmp/proven"
  list_portable_parallel_1 | LC_ALL=C sort -u >"$tmp/s1"
  list_portable_parallel_2 | LC_ALL=C sort -u >"$tmp/s2"

  cat "$tmp/s1" "$tmp/s2" | LC_ALL=C sort | uniq -d >"$tmp/shard_dups"
  if [ -s "$tmp/shard_dups" ]; then
    log "coverage guard: portable parallel shards share scripts:"
    cat "$tmp/shard_dups" >&2
    rm -rf "$tmp"
    return 1
  fi
  cat "$tmp/s1" "$tmp/s2" | LC_ALL=C sort -u >"$tmp/shards_union"
  missing=$(comm -23 "$tmp/proven" "$tmp/shards_union" || true)
  extra=$(comm -13 "$tmp/proven" "$tmp/shards_union" || true)
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    log "coverage guard: portable shards must equal the proven-isolated set"
    [ -z "$missing" ] || { log "missing from shards:"; printf '%s\n' "$missing" >&2; }
    [ -z "$extra" ] || { log "extra beyond proven:"; printf '%s\n' "$extra" >&2; }
    rm -rf "$tmp"
    return 1
  fi

  # Serial (whole lane and each CI shard) + Herdr lane listings without
  # disturbing a caller's selection.
  saved_scripts=("${SCRIPTS[@]+"${SCRIPTS[@]}"}")
  SCRIPTS=()
  select_lane portable-serial
  printf '%s\n' "${SCRIPTS[@]+"${SCRIPTS[@]}"}" | LC_ALL=C sort -u >"$tmp/serial"
  : >"$tmp/serial_shards_raw"
  shard=1
  while [ "$shard" -le "$PORTABLE_SERIAL_SHARDS" ]; do
    SCRIPTS=()
    select_lane "portable-serial-${shard}of${PORTABLE_SERIAL_SHARDS}"
    if [ "${#SCRIPTS[@]}" -eq 0 ]; then
      log "coverage guard: portable serial shard $shard of $PORTABLE_SERIAL_SHARDS is empty"
      SCRIPTS=("${saved_scripts[@]+"${saved_scripts[@]}"}")
      rm -rf "$tmp"
      return 1
    fi
    printf '%s\n' "${SCRIPTS[@]}" >>"$tmp/serial_shards_raw"
    shard=$((shard + 1))
  done
  SCRIPTS=()
  select_family real-herdr-gated
  printf '%s\n' "${SCRIPTS[@]+"${SCRIPTS[@]}"}" | LC_ALL=C sort -u >"$tmp/herdr"
  SCRIPTS=("${saved_scripts[@]+"${saved_scripts[@]}"}")

  # Every serial script runs in exactly one CI shard: no duplicate work across
  # runners, and no script silently left out of the required lane.
  LC_ALL=C sort "$tmp/serial_shards_raw" | uniq -d >"$tmp/serial_shard_dups"
  if [ -s "$tmp/serial_shard_dups" ]; then
    log "coverage guard: portable serial shards share scripts:"
    cat "$tmp/serial_shard_dups" >&2
    rm -rf "$tmp"
    return 1
  fi
  LC_ALL=C sort -u "$tmp/serial_shards_raw" >"$tmp/serial_shards"
  missing=$(comm -23 "$tmp/serial" "$tmp/serial_shards" || true)
  extra=$(comm -13 "$tmp/serial" "$tmp/serial_shards" || true)
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    log "coverage guard: portable serial shards must equal the portable serial lane"
    [ -z "$missing" ] || { log "missing from serial shards:"; printf '%s\n' "$missing" >&2; }
    [ -z "$extra" ] || { log "extra beyond serial lane:"; printf '%s\n' "$extra" >&2; }
    rm -rf "$tmp"
    return 1
  fi

  for pair in "shards_union:serial" "shards_union:herdr" "serial:herdr"; do
    a=${pair%%:*}
    b=${pair#*:}
    comm -12 "$tmp/$a" "$tmp/$b" >"$tmp/overlap"
    if [ -s "$tmp/overlap" ]; then
      log "coverage guard: overlap between $a and $b:"
      cat "$tmp/overlap" >&2
      rm -rf "$tmp"
      return 1
    fi
  done

  cat "$tmp/shards_union" "$tmp/serial" "$tmp/herdr" | LC_ALL=C sort >"$tmp/union_raw"
  uniq -d "$tmp/union_raw" >"$tmp/union_dups"
  if [ -s "$tmp/union_dups" ]; then
    log "coverage guard: duplicate scripts across lanes:"
    cat "$tmp/union_dups" >&2
    rm -rf "$tmp"
    return 1
  fi
  LC_ALL=C sort -u "$tmp/union_raw" >"$tmp/union"
  missing=$(comm -23 "$tmp/all" "$tmp/union" || true)
  extra=$(comm -13 "$tmp/all" "$tmp/union" || true)
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    log "coverage guard: union of portable shards + portable serial + Herdr must equal tests/*.test.sh"
    [ -z "$missing" ] || { log "missing from union:"; printf '%s\n' "$missing" >&2; }
    [ -z "$extra" ] || { log "extra beyond inventory:"; printf '%s\n' "$extra" >&2; }
    rm -rf "$tmp"
    return 1
  fi

  if [ -x "$ROOT/bin/dj-test-isolation-proof.sh" ]; then
    "$ROOT/bin/dj-test-isolation-proof.sh" --list | LC_ALL=C sort -u >"$tmp/proof_list"
    if ! cmp -s "$tmp/proven" "$tmp/proof_list"; then
      log "coverage guard: embedded proven-isolated set diverges from bin/dj-test-isolation-proof.sh --list"
      comm -3 "$tmp/proven" "$tmp/proof_list" >&2 || true
      rm -rf "$tmp"
      return 1
    fi
  fi

  printf 'DJ_TEST_COVERAGE ok total=%s parallel=%s serial=%s serial_shards=%s herdr=%s\n' \
    "$(wc -l <"$tmp/all" | tr -d ' ')" \
    "$(wc -l <"$tmp/shards_union" | tr -d ' ')" \
    "$(wc -l <"$tmp/serial" | tr -d ' ')" \
    "$PORTABLE_SERIAL_SHARDS" \
    "$(wc -l <"$tmp/herdr" | tr -d ' ')"
  rm -rf "$tmp"
  return 0
}

aggregate_timing_json() {
  local out=$1
  shift
  [ "$#" -gt 0 ] || die "--aggregate-json requires at least one input timing JSON"
  command -v python3 >/dev/null 2>&1 || die "--aggregate-json requires python3"
  python3 - "$out" "$@" <<'PY'
import json, sys
from pathlib import Path

out = Path(sys.argv[1])
inputs = [Path(p) for p in sys.argv[2:]]
lanes = []
all_scripts = []
failed = 0
skipped = 0
total = 0
wall_ms = 0
for path in inputs:
    doc = json.loads(path.read_text(encoding="utf-8"))
    summary = doc.get("summary") or {}
    lane = {
        "path": str(path),
        "run_id": doc.get("run_id"),
        "selection": doc.get("selection"),
        "started_at": doc.get("started_at"),
        "finished_at": doc.get("finished_at"),
        "summary": summary,
    }
    lanes.append(lane)
    total += int(summary.get("total") or 0)
    failed += int(summary.get("failed") or 0)
    skipped += int(summary.get("skipped_gate") or 0)
    wall_ms = max(wall_ms, int(summary.get("duration_ms") or 0))
    for s in doc.get("scripts") or []:
        row = dict(s)
        row["lane_selection"] = doc.get("selection")
        row["lane_run_id"] = doc.get("run_id")
        all_scripts.append(row)

all_scripts.sort(key=lambda s: (-int(s.get("duration_ms") or 0), s.get("path") or ""))
agg = {
    "kind": "aggregate",
    "lanes": lanes,
    "summary": {
        "lanes": len(lanes),
        "total": total,
        "failed": failed,
        "skipped_gate": skipped,
        "critical_path_duration_ms": wall_ms,
    },
    "scripts": all_scripts,
    "slowest": all_scripts[:15],
}
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(agg, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"DJ_TEST_AGGREGATE lanes={len(lanes)} total={total} failed={failed} skipped_gate={skipped} critical_path_duration_ms={wall_ms}")
PY
}

all_repo_tests() {
  # Deterministic lexical order (same as bash glob expansion under LC_ALL=C).
  local f
  # shellcheck disable=SC2035
  for f in tests/*.test.sh; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f"
  done | LC_ALL=C sort
}

normalize_script_path() {
  local p=$1
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    tests/*|./tests/*)
      p=${p#./}
      printf '%s\n' "$p"
      ;;
    *.test.sh)
      if [ -f "tests/$p" ]; then
        printf 'tests/%s\n' "$p"
      else
        printf '%s\n' "$p"
      fi
      ;;
    *)
      printf '%s\n' "$p"
      ;;
  esac
}

# Append unique relative-or-absolute script paths to SCRIPTS.
add_script() {
  local p existing
  p=$(normalize_script_path "$1")
  for existing in "${SCRIPTS[@]+"${SCRIPTS[@]}"}"; do
    [ "$existing" = "$p" ] && return 0
  done
  SCRIPTS+=("$p")
}

select_all() {
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    add_script "$s"
  done < <(all_repo_tests)
}

select_family() {
  local want=$1 s base fam found=0
  [ -n "$want" ] || die "--family requires a name"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    base=$(basename "$s")
    fam=$(family_for_basename "$base")
    if [ "$fam" = "$want" ]; then
      add_script "$s"
      found=1
    fi
  done < <(all_repo_tests)
  [ "$found" -eq 1 ] || die "no tests mapped to family '$want'"
}

families_for_test_reference() {
  local needle=$1 s
  local found=0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if grep -Fq "$needle" "$s"; then
      family_for_basename "$(basename "$s")"
      found=1
    fi
  done < <(all_repo_tests)
  [ "$found" -eq 1 ]
}

# Conservative path → family map. Over-selects rather than under-selects.
# Never expands to the complete suite.
families_for_changed_path() {
  local path=$1 fixture_ref
  case "$path" in
    tests/dj-test-run.test.sh)
      printf '%s\n' pure-contract-unit
      ;;
    tests/dj-backend-herdr-eventwait.test.py)
      printf '%s\n' real-herdr-gated
      printf '%s\n' backend-dispatch
      ;;
    tests/*.test.sh)
      # A single test file change selects only that script via basename family
      # resolution in the caller; emit a marker family of __script__
      printf '%s\n' "__script__:$(basename "$path")"
      ;;
    bin/dj-test-run.sh|bin/dj-test-isolation-proof.sh)
      printf '%s\n' pure-contract-unit
      ;;
    bin/backends/herdr*|bin/dj-herdr-lab.sh|tests/herdr-test-safety.sh)
      printf '%s\n' real-herdr-gated
      printf '%s\n' backend-dispatch
      printf '%s\n' pure-contract-unit
      ;;
    bin/dj-herdr-session-cleanup.sh)
      printf '%s\n' session-bootstrap
      printf '%s\n' real-herdr-gated
      printf '%s\n' backend-dispatch
      ;;
    bin/backends/zellij*|tests/zellij-test-safety.sh)
      printf '%s\n' zellij
      printf '%s\n' backend-dispatch
      ;;
    bin/backends/cmux*|tests/cmux-test-safety.sh)
      printf '%s\n' cmux
      printf '%s\n' backend-dispatch
      ;;
    bin/backends/orca*|bin/backends/tmux.sh)
      printf '%s\n' backend-dispatch
      printf '%s\n' orca
      ;;
    bin/dj-backend.sh|bin/dj-backend-hometag-lib.sh)
      printf '%s\n' backend-dispatch
      printf '%s\n' real-herdr-gated
      ;;
    bin/dj-watch*|bin/dj-wake*|bin/dj-inactive-reconcile.sh|\
    bin/dj-classify-lib.sh|bin/dj-daemon*|bin/dj-turnend-guard*|bin/dj-guard.sh)
      printf '%s\n' watcher-wake-lock
      ;;
    bin/dj-afk*)
      printf '%s\n' afk
      printf '%s\n' real-herdr-gated
      ;;
    bin/dj-supervisor-target-lib.sh)
      printf '%s\n' watcher-wake-lock
      printf '%s\n' real-herdr-gated
      printf '%s\n' live-harness-optin
      printf '%s\n' afk
      ;;
    bin/dj-startup-memory-budget.sh|bin/dj-startup-memory-budget-lib.sh)
      printf '%s\n' secondmate
      printf '%s\n' session-bootstrap
      ;;
    bin/dj-secondmate*|bin/dj-remote*|bin/dj-on.sh|bin/dj-home-seed.sh|\
    bin/dj-backlog-handoff.sh|bin/dj-backlog-receive.sh|bin/dj-procevent-remote-reply.sh|\
    bin/dj-config-inherit-lib.sh|bin/dj-config-push.sh|bin/dj-shared*|\
    bin/dj-stow-cascade.sh)
      printf '%s\n' secondmate
      ;;
    bin/dj-session-start.sh|bin/dj-bootstrap.sh|bin/dj-fleet-sync.sh|\
    bin/dj-sessionstart-nudge.sh|bin/dj-startup-network.sh|bin/dj-tangle*|bin/dj-update.sh|\
    bin/dj-gate-refuse*|bin/dj-lock*|bin/dj-quota-axi-lib.sh)
      printf '%s\n' session-bootstrap
      ;;
    bin/dj-sessionstart-run.sh|.claude/settings.json|.codex/hooks.json|\
    .pi/extensions/dj-primary-turnend-guard.ts)
      # The run tier's two harness-supplied facts (source vocabulary and
      # context-reset stdout injection) only show up against a real harness.
      printf '%s\n' session-bootstrap
      printf '%s\n' live-harness-optin
      ;;
    bin/dj-timeout-lib.sh)
      # The shared hard bound: session start's runtime bound, the fleet/bearings
      # snapshots, the vendor auth probe, the stow cascade's per-home step, and
      # the wedge detector's worktree write probe all depend on it.
      printf '%s\n' session-bootstrap
      printf '%s\n' snapshot-bearings
      printf '%s\n' pure-contract-unit
      printf '%s\n' secondmate
      printf '%s\n' watcher-wake-lock
      ;;
    bin/dj-pr-*|bin/dj-merge-local.sh|bin/dj-teardown.sh|bin/dj-review-diff.sh|\
    bin/dj-x-*|bin/dj-check*)
      printf '%s\n' pr-forge
      ;;
    bin/dj-nm-run-lib.sh)
      # Shared no-mistakes run-attribution primitives, sourced by both
      # bin/dj-crew-state.sh (pure-contract-unit) and bin/dj-teardown.sh's
      # pre-teardown run abort (pr-forge).
      printf '%s\n' pure-contract-unit
      printf '%s\n' pr-forge
      ;;
    bin/dj-composer-lib.sh)
      # The shared shape catalogue is vendor-rendered signal; a change to it
      # re-selects the live guard (dj-composer-matrix-live-e2e) alongside the
      # portable families.
      printf '%s\n' backend-dispatch
      printf '%s\n' pure-contract-unit
      printf '%s\n' live-harness-optin
      ;;
    bin/dj-spawn.sh|bin/dj-send.sh|bin/dj-harness.sh|\
    bin/dj-peek.sh|bin/dj-composer*)
      printf '%s\n' backend-dispatch
      printf '%s\n' pure-contract-unit
      ;;
    bin/dj-task-inbox-lib.sh)
      # The steering-inbox record/doorbell/ladder owner: dj-send's data plane
      # (backend-dispatch), the watcher's re-ring check (watcher-wake-lock),
      # and the live doorbell guard against real harnesses.
      printf '%s\n' backend-dispatch
      printf '%s\n' watcher-wake-lock
      printf '%s\n' live-harness-optin
      ;;
    bin/dj-bearings-snapshot.sh|bin/dj-fleet-snapshot.sh|bin/dj-fleet-view.sh)
      printf '%s\n' snapshot-bearings
      ;;
    bin/dj-install-herdr.sh|bin/dj-install-treehouse.sh|bin/dj-herdr-ci-cleanup.sh)
      printf '%s\n' pure-contract-unit
      # Pin or cleanup changes also select the real-Herdr family so the required
      # lane's contract coverage re-runs.
      printf '%s\n' real-herdr-gated
      ;;
    bin/dj-lint.sh|bin/dj-lint-workflows.sh|bin/dj-install-shellcheck.sh|\
    bin/dj-install-actionlint.sh|\
    bin/dj-brief.sh|bin/dj-ensure-agents-md.sh|bin/dj-crew-state.sh|\
    bin/dj-captain-hold.sh|bin/dj-decision-hold.sh|bin/dj-supervision*|bin/dj-transition-lib.sh|\
    bin/dj-tmux-lib.sh|bin/dj-marker-lib.sh|bin/dj-operational-input.sh|bin/dj-tasks-axi-lib.sh|\
    bin/dj-vendor-auth-probe.sh|\
    bin/dj-primary-scope-lib.sh|bin/dj-project-mode.sh|bin/dj-promote.sh|\
    bin/dj-ff-lib.sh|bin/dj-gotmp*|bin/*pretool*)
      printf '%s\n' pure-contract-unit
      ;;
    .agents/skills/quota-array-dispatch/SKILL.md)
      printf '%s\n' pure-contract-unit
      printf '%s\n' live-harness-optin
      ;;
    .agents/skills/*/SKILL.md)
      printf '%s\n' pure-contract-unit
      ;;
    .github/workflows/ci.yml|.no-mistakes.yaml)
      printf '%s\n' pure-contract-unit
      printf '%s\n' real-herdr-gated
      ;;
    docs/dj-test-portable-shards.md|docs/dj-test-isolation-proof.md|\
    docs/dj-test-isolation-proof.json)
      printf '%s\n' pure-contract-unit
      ;;
    .github/*|.tasks.toml|AGENTS.md|CLAUDE.md|CONTRIBUTING.md|\
    docs/configuration.md|docs/supervision-protocols/*)
      printf '%s\n' pure-contract-unit
      ;;
    tests/lib.sh|tests/*-helpers.sh)
      families_for_test_reference "$(basename "$path")" \
        || printf '%s\n' "__unmapped__:$path"
      ;;
    tests/fixtures/*/*)
      # A fixture belongs to whichever suite reads its directory, found by the
      # same reference scan used for shared helpers. Keyed on the directory
      # rather than the file so adding a fixture selects the same suite.
      # A removed fixture directory has no consuming suite left to select.
      fixture_ref=${path#tests/fixtures/}
      fixture_ref=${fixture_ref%%/*}
      if [ -d "tests/fixtures/$fixture_ref" ]; then
        families_for_test_reference "fixtures/$fixture_ref" \
          || printf '%s\n' "__unmapped__:$path"
      fi
      ;;
    bin/*)
      # A deleted script has no consuming suite left to select, the same rule
      # the fixture case above applies. Refusing on its absent mapping would
      # make every retirement branch unable to select its changed tests.
      if [ -e "$path" ]; then
        families_for_test_reference "$(basename "$path")" \
          || printf '%s\n' "__unmapped__:$path"
      fi
      ;;
    tests/*)
      printf '%s\n' "__unmapped__:$path"
      ;;
    README.md|LICENSE|assets/*|docs/*|.gitignore)
      ;;
    *)
      families_for_test_reference "$path" \
        || printf '%s\n' "__unmapped__:$path"
      ;;
  esac
}

select_changed() {
  local base=$1 path entry fam script_name s
  local -a wanted_families=()
  local -a wanted_scripts=()

  if ! git -C "$ROOT" rev-parse --verify "$base" >/dev/null 2>&1; then
    die "changed-file base ref not found: $base (pass --base <ref>)"
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      case "$entry" in
        __script__:*)
          script_name=${entry#__script__:}
          wanted_scripts+=("$script_name")
          ;;
        __unmapped__:*)
          die "no changed-test mapping for source path: ${entry#__unmapped__:}"
          ;;
        *)
          wanted_families+=("$entry")
          ;;
      esac
    done < <(families_for_changed_path "$path")
  done < <(git -C "$ROOT" diff --name-only "${base}...HEAD" 2>/dev/null; \
           git -C "$ROOT" diff --name-only HEAD 2>/dev/null; \
           git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null)

  # Dedup families
  local f seen_f
  local -a unique_families=()
  for f in "${wanted_families[@]+"${wanted_families[@]}"}"; do
    seen_f=0
    for u in "${unique_families[@]+"${unique_families[@]}"}"; do
      [ "$u" = "$f" ] && { seen_f=1; break; }
    done
    [ "$seen_f" -eq 0 ] && unique_families+=("$f")
  done

  for f in "${unique_families[@]+"${unique_families[@]}"}"; do
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      if [ "$(family_for_basename "$(basename "$s")")" = "$f" ]; then
        add_script "$s"
      fi
    done < <(all_repo_tests)
  done

  for script_name in "${wanted_scripts[@]+"${wanted_scripts[@]}"}"; do
    if [ -f "tests/$script_name" ]; then
      add_script "tests/$script_name"
    fi
  done

  if [ "${#SCRIPTS[@]}" -eq 0 ]; then
    log "no tests selected for changes vs $base (map is conservative; use --all for the complete suite)"
  fi
}

detect_gate_skip() {
  # True when the first non-empty output line is a skip: gate message.
  local file=$1 first
  first=$(awk 'NF { print; exit }' "$file" 2>/dev/null || true)
  case "$first" in
    skip:*) return 0 ;;
    *) return 1 ;;
  esac
}

# True when any output line contains "skip: <token>" (token may contain spaces).
detect_gate_skip_token() {
  local file=$1 token=$2
  [ -n "$token" ] || return 1
  grep -F -q "skip: $token" "$file" 2>/dev/null
}

apply_exclude_families() {
  local s fam keep ex
  local -a kept=()
  [ "${#EXCLUDE_FAMILIES[@]}" -gt 0 ] || return 0
  for s in "${SCRIPTS[@]+"${SCRIPTS[@]}"}"; do
    fam=$(family_for_basename "$(basename "$s")")
    keep=1
    for ex in "${EXCLUDE_FAMILIES[@]}"; do
      if [ "$fam" = "$ex" ]; then
        keep=0
        break
      fi
    done
    [ "$keep" -eq 1 ] && kept+=("$s")
  done
  SCRIPTS=("${kept[@]+"${kept[@]}"}")
}

write_json_artifact() {
  local out=$1
  local started=$2
  local finished=$3
  local run_id=$4
  local total=$5
  local failed=$6
  local skipped=$7
  local duration=$8
  local selection=$9
  local records_file=${10}
  local families_file=${11}

  if ! command -v python3 >/dev/null 2>&1; then
    die "--json requires python3 to emit a valid timing artifact"
  fi

  python3 - "$out" "$started" "$finished" "$run_id" "$total" "$failed" "$skipped" "$duration" "$selection" "$records_file" "$families_file" <<'PY'
import json, sys

out, started, finished, run_id, total, failed, skipped, duration, selection, records_file, families_file = sys.argv[1:]

scripts = []
with open(records_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        path, family, expected, exit_s, dur_s, gate = line.split("\t")
        scripts.append({
            "path": path,
            "family": family,
            "expected_gate_skip": expected,
            "duration_ms": int(dur_s),
            "exit": int(exit_s),
            "gate_skip": gate == "true",
        })

families = []
with open(families_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        name, count_s, dur_s, failed_s = line.split("\t")
        families.append({
            "name": name,
            "count": int(count_s),
            "duration_ms": int(dur_s),
            "failed": int(failed_s),
        })

doc = {
    "run_id": run_id,
    "started_at": started,
    "finished_at": finished,
    "selection": selection,
    "summary": {
        "total": int(total),
        "failed": int(failed),
        "skipped_gate": int(skipped),
        "duration_ms": int(duration),
    },
    "scripts": scripts,
    "families": families,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=all
      shift
      ;;
    --family)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      [ "$#" -gt 1 ] || die "--family requires a name"
      MODE=family
      FAMILY=$2
      shift 2
      ;;
    --family=*)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=family
      FAMILY=${1#--family=}
      shift
      ;;
    --lane)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      [ "$#" -gt 1 ] || die "--lane requires a name (see --list-lanes)"
      MODE=lane
      LANE=$2
      shift 2
      ;;
    --lane=*)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=lane
      LANE=${1#--lane=}
      shift
      ;;
    --proven-isolated)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=proven-isolated
      shift
      ;;
    --changed)
      [ -z "$MODE" ] || die "only one selection mode is allowed"
      MODE=changed
      shift
      ;;
    --base)
      [ "$#" -gt 1 ] || die "--base requires a git ref"
      BASE_REF=$2
      shift 2
      ;;
    --base=*)
      BASE_REF=${1#--base=}
      shift
      ;;
    --json)
      [ "$#" -gt 1 ] || die "--json requires a path"
      JSON_PATH=$2
      shift 2
      ;;
    --json=*)
      JSON_PATH=${1#--json=}
      shift
      ;;
    --jobs)
      [ "$#" -gt 1 ] || die "--jobs requires a positive integer"
      JOBS=$2
      shift 2
      ;;
    --jobs=*)
      JOBS=${1#--jobs=}
      shift
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --list-families)
      LIST_FAMILIES=1
      shift
      ;;
    --list-lanes)
      LIST_LANES=1
      shift
      ;;
    --check-coverage)
      CHECK_COVERAGE=1
      shift
      ;;
    --aggregate-json)
      [ "$#" -gt 1 ] || die "--aggregate-json requires an output path"
      AGGREGATE_OUT=$2
      shift 2
      # Remaining args after options will be collected as inputs below via MODE.
      # For aggregation we accept only input JSON paths as free args after this.
      MODE=aggregate
      ;;
    --exclude-family)
      [ "$#" -gt 1 ] || die "--exclude-family requires a name"
      EXCLUDE_FAMILIES+=("$2")
      shift 2
      ;;
    --exclude-family=*)
      EXCLUDE_FAMILIES+=("${1#--exclude-family=}")
      shift
      ;;
    --fail-on-gate-skip)
      [ "$#" -gt 1 ] || die "--fail-on-gate-skip requires a token (e.g. 'herdr not found')"
      FAIL_ON_GATE_SKIP=$2
      shift 2
      ;;
    --fail-on-gate-skip=*)
      FAIL_ON_GATE_SKIP=${1#--fail-on-gate-skip=}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        SCRIPTS+=("$1")
        shift
      done
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [ "${MODE:-}" = "aggregate" ]; then
        SCRIPTS+=("$1")
      elif [ -z "$MODE" ] || [ "$MODE" = scripts ]; then
        MODE=scripts
        SCRIPTS+=("$1")
      else
        die "script paths cannot be combined with --$MODE"
      fi
      shift
      ;;
  esac
done

if [ "$LIST_FAMILIES" -eq 1 ]; then
  list_known_families
  exit 0
fi

if [ "$LIST_LANES" -eq 1 ]; then
  list_known_lanes
  exit 0
fi

if [ "$CHECK_COVERAGE" -eq 1 ]; then
  run_coverage_guard
  exit $?
fi

if [ "${MODE:-}" = "aggregate" ]; then
  [ -n "$AGGREGATE_OUT" ] || die "--aggregate-json requires an output path"
  [ "${#SCRIPTS[@]}" -gt 0 ] || die "--aggregate-json requires at least one input timing JSON"
  for s in "${SCRIPTS[@]}"; do
    [ -f "$s" ] || die "aggregate input not found: $s"
  done
  aggregate_timing_json "$AGGREGATE_OUT" "${SCRIPTS[@]}"
  exit 0
fi

case "$JOBS" in
  ''|*[!0-9]*) die "--jobs must be a positive integer" ;;
esac
[ "$JOBS" -ge 1 ] || die "--jobs must be >= 1"
[ "$JOBS" -le "$JOBS_MAX" ] || die "--jobs is capped at $JOBS_MAX (got $JOBS)"

case "${MODE:-}" in
  all)
    select_all
    SELECTION_DESC="all"
    ;;
  family)
    select_family "$FAMILY"
    SELECTION_DESC="family=$FAMILY"
    ;;
  lane)
    select_lane "$LANE"
    SELECTION_DESC="lane=$LANE"
    ;;
  proven-isolated)
    select_proven_isolated
    SELECTION_DESC="proven-isolated"
    ;;
  changed)
    select_changed "$BASE_REF"
    SELECTION_DESC="changed:base=$BASE_REF"
    ;;
  scripts)
    # Normalize and re-add through add_script for consistent paths.
    raw=("${SCRIPTS[@]}")
    SCRIPTS=()
    for s in "${raw[@]}"; do
      add_script "$s"
    done
    SELECTION_DESC="scripts"
    ;;
  *)
    die "select with --all, --family <name>, --lane <name>, --proven-isolated, --changed, or one or more script paths (see --help)"
    ;;
esac

apply_exclude_families
if [ "${#EXCLUDE_FAMILIES[@]}" -gt 0 ]; then
  SELECTION_DESC="${SELECTION_DESC};exclude-family=$(IFS=,; printf '%s' "${EXCLUDE_FAMILIES[*]}")"
fi
if [ -n "$FAIL_ON_GATE_SKIP" ]; then
  SELECTION_DESC="${SELECTION_DESC};fail-on-gate-skip=$FAIL_ON_GATE_SKIP"
fi
if [ "$JOBS" -gt 1 ]; then
  SELECTION_DESC="${SELECTION_DESC};jobs=$JOBS"
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  for s in "${SCRIPTS[@]+"${SCRIPTS[@]}"}"; do
    printf '%s\n' "$s"
  done
  exit 0
fi

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  log "nothing to run"
  printf 'DJ_TEST_SUMMARY total=0 failed=0 skipped_gate=0 duration_ms=0\n'
  if [ -n "$JSON_PATH" ]; then
    empty_rec=$(mktemp)
    empty_fam=$(mktemp)
    : >"$empty_rec"
    : >"$empty_fam"
    started=$(now_iso)
    mkdir -p "$(dirname "$JSON_PATH")"
    write_json_artifact "$JSON_PATH" "$started" "$started" "empty" 0 0 0 0 "$SELECTION_DESC" "$empty_rec" "$empty_fam"
    rm -f "$empty_rec" "$empty_fam"
  fi
  exit 0
fi

# Verify selected scripts exist before starting.
for s in "${SCRIPTS[@]}"; do
  [ -f "$s" ] || die "test script not found: $s"
  [ -x "$s" ] || [ -r "$s" ] || die "test script not readable: $s"
done

# --jobs N>1 only for the proven-isolated set. Stateful families stay serial.
if [ "$JOBS" -gt 1 ]; then
  for s in "${SCRIPTS[@]}"; do
    if ! is_proven_isolated_script "$s"; then
      die "--jobs $JOBS refused: $s is not in the proven-isolated set (see bin/dj-test-isolation-proof.sh --list). Stateful families stay serial."
    fi
  done
fi

RUN_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dj-test-run.XXXXXX")
RECORDS="$RUN_TMP/records.tsv"
FAMILIES_TSV="$RUN_TMP/families.tsv"
: >"$RECORDS"
trap 'rm -rf "$RUN_TMP"' EXIT

RUN_STARTED_ISO=$(now_iso)
RUN_STARTED_MS=$(now_ms)
RUN_ID="dj-test-run-${RUN_STARTED_MS}-$$"
TOTAL=0
FAILED=0
SKIPPED_GATE=0
AGG_RC=0

# Family accumulators as TSV lines updated in-memory via temp files.
# family -> count, duration_ms, failed
family_bump() {
  local fam=$1 dur=$2 failed_delta=$3
  local line name count duration failed_count rest
  local found=0
  local tmp="$RUN_TMP/families.new"
  : >"$tmp"
  if [ -s "$FAMILIES_TSV" ]; then
    while IFS= read -r line; do
      name=${line%%$'\t'*}
      rest=${line#*$'\t'}
      count=${rest%%$'\t'*}
      rest=${rest#*$'\t'}
      duration=${rest%%$'\t'*}
      failed_count=${rest#*$'\t'}
      if [ "$name" = "$fam" ]; then
        count=$((count + 1))
        duration=$((duration + dur))
        failed_count=$((failed_count + failed_delta))
        found=1
      fi
      printf '%s\t%s\t%s\t%s\n' "$name" "$count" "$duration" "$failed_count" >>"$tmp"
    done <"$FAMILIES_TSV"
  fi
  if [ "$found" -eq 0 ]; then
    printf '%s\t%s\t%s\t%s\n' "$fam" 1 "$dur" "$failed_delta" >>"$tmp"
  fi
  mv "$tmp" "$FAMILIES_TSV"
}

record_script_result() {
  local script=$1 rc=$2 duration=$3 out=$4 end_iso=$5
  local base family expected gate_skip fail_delta
  base=$(basename "$script")
  family=$(family_for_basename "$base")
  expected=$(expected_gate_skip_for_family "$family")

  if [ -n "$FAIL_ON_GATE_SKIP" ] && detect_gate_skip_token "$out" "$FAIL_ON_GATE_SKIP"; then
    log "required gate skip token seen in $script: skip: $FAIL_ON_GATE_SKIP"
    rc=1
  fi

  gate_skip=false
  if [ "$rc" -eq 0 ] && detect_gate_skip "$out"; then
    gate_skip=true
    SKIPPED_GATE=$((SKIPPED_GATE + 1))
  fi

  printf 'DJ_TEST_END %s %s exit=%s duration_ms=%s gate_skip=%s\n' \
    "$end_iso" "$script" "$rc" "$duration" "$gate_skip"

  fail_delta=0
  if [ "$rc" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    fail_delta=1
    AGG_RC=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$script" "$family" "$expected" "$rc" "$duration" "$gate_skip" >>"$RECORDS"
  family_bump "$family" "$duration" "$fail_delta"
  TOTAL=$((TOTAL + 1))
}

run_one_serial() {
  local script=$1
  local base family expected out begin_iso begin_ms end_ms end_iso duration rc
  base=$(basename "$script")
  family=$(family_for_basename "$base")
  expected=$(expected_gate_skip_for_family "$family")
  out="$RUN_TMP/out.$TOTAL"
  begin_iso=$(now_iso)
  begin_ms=$(now_ms)

  printf 'DJ_TEST_BEGIN %s %s family=%s expected_gate_skip=%s\n' \
    "$begin_iso" "$script" "$family" "$expected"

  set +e
  # Stream live output while retaining a copy for gate-skip detection.
  # PIPESTATUS[0] is the test script; tee's exit is ignored for aggregate.
  bash "$script" 2>&1 | tee "$out"
  rc=${PIPESTATUS[0]}
  set -e
  : "${rc:=1}"

  end_ms=$(now_ms)
  end_iso=$(now_iso)
  duration=$((end_ms - begin_ms))
  if [ "$duration" -lt 0 ]; then
    duration=0
  fi
  record_script_result "$script" "$rc" "$duration" "$out" "$end_iso"
}

if [ "$JOBS" -eq 1 ]; then
  for script in "${SCRIPTS[@]}"; do
    run_one_serial "$script"
  done
else
  # Bounded concurrent execution for proven-isolated scripts only. Each worker
  # gets a private mode-0700 TMPDIR so mktemp roots cannot collide. Retries are
  # never used as a green strategy.
  declare -a WORKER_PIDS=()
  declare -a WORKER_IDX=()
  declare -a WORKER_SCRIPTS=()
  worker_n=0
  active_workers=0

  wait_one_job_worker() {
    local slot=$1 pid idx work script rc duration mode out end_iso
    pid=${WORKER_PIDS[$slot]}
    idx=${WORKER_IDX[$slot]}
    script=${WORKER_SCRIPTS[$slot]}
    unset 'WORKER_PIDS[slot]'
    unset 'WORKER_IDX[slot]'
    unset 'WORKER_SCRIPTS[slot]'
    active_workers=$((active_workers - 1))
    set +e
    wait "$pid"
    set -e
    work="$RUN_TMP/w$idx"
    rc=$(cat "$work/exit" 2>/dev/null || echo 1)
    duration=$(cat "$work/duration_ms" 2>/dev/null || echo 0)
    out="$work/output"
    end_iso=$(now_iso)
    # Replay captured output after the worker finishes so markers stay ordered.
    if [ -s "$out" ]; then
      cat "$out"
    fi
    mode=$(stat -c %a "$work" 2>/dev/null || stat -f %Lp "$work" 2>/dev/null || echo unknown)
    case "$mode" in
      700|0700) ;;
      *)
        log "isolation failure: worker root mode is $mode, expected 0700 ($work)"
        rc=1
        ;;
    esac
    record_script_result "$script" "$rc" "$duration" "$out" "$end_iso"
  }

  worker_pid_is_running() {
    local want=$1 running inventory="$RUN_TMP/running-pids"
    # Keep `jobs` in this shell. A process substitution runs it in a subshell
    # without this shell's job table on Bash 3.2/5.x, falsely reporting every
    # worker complete and making the scheduler wait for the oldest PID.
    jobs -r -p >"$inventory"
    while IFS= read -r running; do
      [ "$running" = "$want" ] && return 0
    done <"$inventory"
    return 1
  }

  wait_one_completed_job_worker() {
    local slot work
    while :; do
      for slot in "${!WORKER_PIDS[@]}"; do
        work="$RUN_TMP/w${WORKER_IDX[$slot]}"
        if [ -f "$work/exit" ] || ! worker_pid_is_running "${WORKER_PIDS[$slot]}"; then
          wait_one_job_worker "$slot"
          return
        fi
      done
      sleep 0.01
    done
  }

  for script in "${SCRIPTS[@]}"; do
    while [ "$active_workers" -ge "$JOBS" ]; do
      wait_one_completed_job_worker
    done
    worker_n=$((worker_n + 1))
    work="$RUN_TMP/w$worker_n"
    mkdir -p "$work/tmp"
    chmod 0700 "$work" "$work/tmp" || die "could not chmod 0700 worker root $work"
    base=$(basename "$script")
    family=$(family_for_basename "$base")
    expected=$(expected_gate_skip_for_family "$family")
    printf 'DJ_TEST_BEGIN %s %s family=%s expected_gate_skip=%s\n' \
      "$(now_iso)" "$script" "$family" "$expected"
    (
      set +e
      export TMPDIR="$work/tmp"
      export TMP="$work/tmp"
      unset DJ_HOME DJ_STATE_OVERRIDE DJ_DATA_OVERRIDE DJ_ROOT_OVERRIDE \
        DJ_PROJECTS_OVERRIDE DJ_CONFIG_OVERRIDE DJ_BACKEND 2>/dev/null || true
      cd "$ROOT" || exit 1
      begin_ms=$(now_ms)
      bash "$script" >"$work/output" 2>&1
      rc=$?
      end_ms=$(now_ms)
      duration=$((end_ms - begin_ms))
      if [ "$duration" -lt 0 ]; then
        duration=0
      fi
      printf '%s\n' "$duration" >"$work/duration_ms"
      printf '%s\n' "$rc" >"$work/exit"
      exit 0
    ) &
    WORKER_PIDS[worker_n]=$!
    WORKER_IDX[worker_n]=$worker_n
    WORKER_SCRIPTS[worker_n]=$script
    active_workers=$((active_workers + 1))
  done
  while [ "$active_workers" -gt 0 ]; do
    wait_one_completed_job_worker
  done
fi

RUN_FINISHED_ISO=$(now_iso)
RUN_FINISHED_MS=$(now_ms)
RUN_DURATION=$((RUN_FINISHED_MS - RUN_STARTED_MS))
if [ "$RUN_DURATION" -lt 0 ]; then
  RUN_DURATION=0
fi

printf 'DJ_TEST_SUMMARY total=%s failed=%s skipped_gate=%s duration_ms=%s\n' \
  "$TOTAL" "$FAILED" "$SKIPPED_GATE" "$RUN_DURATION"

if [ -s "$FAMILIES_TSV" ]; then
  # Stable family summary order by name.
  sort -t$'\t' -k1,1 "$FAMILIES_TSV" | while IFS=$'\t' read -r name count duration failed_count; do
    printf 'DJ_TEST_SUMMARY_FAMILY family=%s count=%s duration_ms=%s failed=%s\n' \
      "$name" "$count" "$duration" "$failed_count"
  done
fi

# Slowest scripts (top 15) from records.
if [ -s "$RECORDS" ]; then
  rank=1
  sort -t$'\t' -k5,5nr "$RECORDS" | head -n 15 | while IFS=$'\t' read -r path _family _expected _rc duration _gate; do
    printf 'DJ_TEST_SLOWEST rank=%s script=%s duration_ms=%s\n' \
      "$rank" "$path" "$duration"
    rank=$((rank + 1))
  done
fi

if [ -n "$JSON_PATH" ]; then
  mkdir -p "$(dirname "$JSON_PATH")"
  # Families file may be unsorted; write_json reads as-is (deterministic sort in python).
  if [ -s "$FAMILIES_TSV" ]; then
    sort -t$'\t' -k1,1 "$FAMILIES_TSV" -o "$FAMILIES_TSV"
  else
    : >"$FAMILIES_TSV"
  fi
  write_json_artifact "$JSON_PATH" \
    "$RUN_STARTED_ISO" "$RUN_FINISHED_ISO" "$RUN_ID" \
    "$TOTAL" "$FAILED" "$SKIPPED_GATE" "$RUN_DURATION" \
    "$SELECTION_DESC" "$RECORDS" "$FAMILIES_TSV"
  log "wrote timing artifact: $JSON_PATH"
fi

exit "$AGG_RC"

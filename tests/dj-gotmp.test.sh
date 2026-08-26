#!/usr/bin/env bash
# Behavior tests for per-task GOTMPDIR support (dj-gotmp).
#
# dj-spawn gives each task a temp root /tmp/dj-<id>/ with Go's build temp nested at
# gotmp/, exports GOTMPDIR into the crewmate pane, and records tasktmp= in the task's
# meta. dj-teardown reads tasktmp= and removes the whole root on cleanup.
#
# These tests exercise dj-teardown directly as a subprocess against a fake DJ_HOME/DJ_ROOT
# built so the real script resolves into it, with stub helper scripts.
# The isolated dj-spawn subprocess in dj-kimi-harness.test.sh covers temp-root creation,
# metadata publication, and the pane environment export.
set -u

# This suite does not source tests/lib.sh, so exempt its teardown subprocess from
# the gate-lifecycle refusal (bin/dj-gate-refuse-lib.sh) the way lib.sh does for
# the rest of the suite: the no-mistakes gate runs this suite from a gate worktree,
# which the guard would otherwise refuse.
export DJ_GATE_REFUSE_BYPASS=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEARDOWN="$ROOT/bin/dj-teardown.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

TMP_ROOT=

cleanup() {
  if [ -n "${TMP_ROOT:-}" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/dj-gotmp-tests.XXXXXX")

# Build a fake DJ_HOME/DJ_ROOT so the real dj-teardown.sh (symlinked in) resolves
# state and helper scripts inside it. Stub the helper scripts dj-teardown calls so no
# live tmux/treehouse/fleet state is touched. A nonexistent worktree path makes both
# `if [ -d "$WT" ]` guards skip, so teardown runs straight to the cleanup + state rm.
make_fake_root() {
  local id=$1 tasktmp=$2
  local fake="$TMP_ROOT/$id"
  mkdir -p "$fake/bin/backends" "$fake/state"
  # Symlink the REAL teardown so the test exercises actual code, not a copy.
  ln -s "$TEARDOWN" "$fake/bin/dj-teardown.sh"
  # dj-backend.sh + its tmux adapter: symlink the REAL files (teardown sources
  # dj-backend.sh unconditionally, and dispatches the kill call through the
  # tmux adapter; both are unchanged by this suite's fixture, just newly
  # required siblings since the P1 backend extraction).
  ln -s "$ROOT/bin/dj-backend.sh" "$fake/bin/dj-backend.sh"
  ln -s "$ROOT/bin/backends/tmux.sh" "$fake/bin/backends/tmux.sh"
  ln -s "$ROOT/bin/dj-tmux-lib.sh" "$fake/bin/dj-tmux-lib.sh"
  ln -s "$ROOT/bin/dj-cursor-lib.sh" "$fake/bin/dj-cursor-lib.sh"
  ln -s "$ROOT/bin/dj-composer-lib.sh" "$fake/bin/dj-composer-lib.sh"
  ln -s "$ROOT/bin/dj-nm-run-lib.sh" "$fake/bin/dj-nm-run-lib.sh"
  # dj-lock-lib.sh: teardown sources it for the shared lock-staleness proof.
  ln -s "$ROOT/bin/dj-lock-lib.sh" "$fake/bin/dj-lock-lib.sh"
  # dj-lease-lib.sh: teardown sources it for the supervision lease guard.
  ln -s "$ROOT/bin/dj-lease-lib.sh" "$fake/bin/dj-lease-lib.sh"
  # Lifecycle serialization, status presentation retirement, and shared adapter
  # ownership are sourced by teardown.
  ln -s "$ROOT/bin/dj-control-lib.sh" "$fake/bin/dj-control-lib.sh"
  ln -s "$ROOT/bin/dj-classify-lib.sh" "$fake/bin/dj-classify-lib.sh"
  # dj-timeout-lib.sh: the shared hard bound dj-classify-lib.sh sources for the
  # wedge detector's bounded worktree write probe.
  ln -s "$ROOT/bin/dj-timeout-lib.sh" "$fake/bin/dj-timeout-lib.sh"
  ln -s "$ROOT/bin/dj-wake-lib.sh" "$fake/bin/dj-wake-lib.sh"
  # dj-gate-refuse-lib.sh: teardown sources it before any fleet mutation.
  ln -s "$ROOT/bin/dj-gate-refuse-lib.sh" "$fake/bin/dj-gate-refuse-lib.sh"
  # dj-pr-lib.sh: teardown uses its canonical task-ID validator for poll cleanup.
  ln -s "$ROOT/bin/dj-pr-lib.sh" "$fake/bin/dj-pr-lib.sh"
  # dj-public-followup-lib.sh (and the dj-x-lib.sh it sources): teardown sources
  # it for the relay-activation gate on the promised-public-reply check. Neither
  # does anything in this fixture, which has no .env, but both are real siblings
  # teardown now requires.
  ln -s "$ROOT/bin/dj-public-followup-lib.sh" "$fake/bin/dj-public-followup-lib.sh"
  ln -s "$ROOT/bin/dj-x-lib.sh" "$fake/bin/dj-x-lib.sh"
  ln -s "$ROOT/bin/dj-secondmate-registry-lib.sh" "$fake/bin/dj-secondmate-registry-lib.sh"
  ln -s "$ROOT/bin/dj-secondmate-parent-lib.sh" "$fake/bin/dj-secondmate-parent-lib.sh"
  # Receiver-wake retirement sources the pending-reply library, which in turn
  # requires the marker helper even for this ordinary-task teardown fixture.
  ln -s "$ROOT/bin/dj-pending-reply-lib.sh" "$fake/bin/dj-pending-reply-lib.sh"
  ln -s "$ROOT/bin/dj-marker-lib.sh" "$fake/bin/dj-marker-lib.sh"
  ln -s "$ROOT/bin/dj-operational-input.sh" "$fake/bin/dj-operational-input.sh"
  # dj-guard.sh: stub (teardown calls it with `|| true`).
  cat > "$fake/bin/dj-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fake/bin/dj-guard.sh"
  # dj-fleet-sync.sh: stub (called for non-scout/non-local-only teardowns).
  cat > "$fake/bin/dj-fleet-sync.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fake/bin/dj-fleet-sync.sh"
  # dj-tasks-axi-lib.sh: stub (teardown sources it). Report no backend so
  # backlog_refresh_reminder takes the plain-message path; no tasks-axi here.
  cat > "$fake/bin/dj-tasks-axi-lib.sh" <<'SH'
dj_tasks_axi_backend_available() { return 1; }
SH
  # Meta with a nonexistent worktree so the dirty/treehouse blocks skip.
  cat > "$fake/state/$id.meta" <<META
window=fakeses:dj-$id
worktree=$TMP_ROOT/nonexistent-worktree-$id
project=$TMP_ROOT/nonexistent-project-$id
harness=claude
kind=ship
mode=no-mistakes
yolo=off
tasktmp=$tasktmp
META
  printf '%s' "$fake"
}

# --- dj-teardown side (real subprocess) ---

test_teardown_removes_tasktmp_dir() {
  local id=td-rm-z2
  local task_tmp="$TMP_ROOT/dj-$id"
  mkdir -p "$task_tmp/gotmp"
  printf 'leftover\n' > "$task_tmp/gotmp/build-artifact"
  local fake
  fake=$(make_fake_root "$id" "$task_tmp")
  # Sanity: dir + contents exist before teardown.
  [ -d "$task_tmp/gotmp" ] || fail "precondition: gotmp missing before teardown"
  # Run the REAL teardown against the fake root.
  DJ_HOME="$fake" bash "$fake/bin/dj-teardown.sh" "$id" >/dev/null 2>&1 \
    || fail "teardown exited non-zero with a valid tasktmp"
  [ ! -e "$task_tmp" ] \
    || fail "teardown did not remove the tasktmp dir ($task_tmp still exists)"
  pass "dj-teardown removes the dir pointed to by tasktmp= in meta"
}

test_teardown_skips_gracefully_without_tasktmp() {
  # Backward compat: a meta from a pre-fix task has no tasktmp= line. Teardown must
  # not error and must not remove anything.
  local id=td-absent-z3
  local fake="$TMP_ROOT/$id-root"
  mkdir -p "$fake/bin/backends" "$fake/state"
  ln -s "$TEARDOWN" "$fake/bin/dj-teardown.sh"
  ln -s "$ROOT/bin/dj-backend.sh" "$fake/bin/dj-backend.sh"
  ln -s "$ROOT/bin/backends/tmux.sh" "$fake/bin/backends/tmux.sh"
  ln -s "$ROOT/bin/dj-tmux-lib.sh" "$fake/bin/dj-tmux-lib.sh"
  ln -s "$ROOT/bin/dj-cursor-lib.sh" "$fake/bin/dj-cursor-lib.sh"
  ln -s "$ROOT/bin/dj-composer-lib.sh" "$fake/bin/dj-composer-lib.sh"
  ln -s "$ROOT/bin/dj-nm-run-lib.sh" "$fake/bin/dj-nm-run-lib.sh"
  ln -s "$ROOT/bin/dj-lock-lib.sh" "$fake/bin/dj-lock-lib.sh"
  # dj-lease-lib.sh: teardown sources it for the supervision lease guard.
  ln -s "$ROOT/bin/dj-lease-lib.sh" "$fake/bin/dj-lease-lib.sh"
  ln -s "$ROOT/bin/dj-control-lib.sh" "$fake/bin/dj-control-lib.sh"
  ln -s "$ROOT/bin/dj-classify-lib.sh" "$fake/bin/dj-classify-lib.sh"
  # dj-timeout-lib.sh: the shared hard bound dj-classify-lib.sh sources for the
  # wedge detector's bounded worktree write probe.
  ln -s "$ROOT/bin/dj-timeout-lib.sh" "$fake/bin/dj-timeout-lib.sh"
  ln -s "$ROOT/bin/dj-wake-lib.sh" "$fake/bin/dj-wake-lib.sh"
  # dj-gate-refuse-lib.sh: teardown sources it before any fleet mutation.
  ln -s "$ROOT/bin/dj-gate-refuse-lib.sh" "$fake/bin/dj-gate-refuse-lib.sh"
  # dj-pr-lib.sh: teardown uses its canonical task-ID validator for poll cleanup.
  ln -s "$ROOT/bin/dj-pr-lib.sh" "$fake/bin/dj-pr-lib.sh"
  # dj-public-followup-lib.sh (and the dj-x-lib.sh it sources): teardown sources
  # it for the relay-activation gate on the promised-public-reply check. Neither
  # does anything in this fixture, which has no .env, but both are real siblings
  # teardown now requires.
  ln -s "$ROOT/bin/dj-public-followup-lib.sh" "$fake/bin/dj-public-followup-lib.sh"
  ln -s "$ROOT/bin/dj-x-lib.sh" "$fake/bin/dj-x-lib.sh"
  ln -s "$ROOT/bin/dj-secondmate-registry-lib.sh" "$fake/bin/dj-secondmate-registry-lib.sh"
  ln -s "$ROOT/bin/dj-secondmate-parent-lib.sh" "$fake/bin/dj-secondmate-parent-lib.sh"
  ln -s "$ROOT/bin/dj-pending-reply-lib.sh" "$fake/bin/dj-pending-reply-lib.sh"
  ln -s "$ROOT/bin/dj-marker-lib.sh" "$fake/bin/dj-marker-lib.sh"
  ln -s "$ROOT/bin/dj-operational-input.sh" "$fake/bin/dj-operational-input.sh"
  cat > "$fake/bin/dj-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fake/bin/dj-guard.sh"
  cat > "$fake/bin/dj-fleet-sync.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fake/bin/dj-fleet-sync.sh"
  cat > "$fake/bin/dj-tasks-axi-lib.sh" <<'SH'
dj_tasks_axi_backend_available() { return 1; }
SH
  # No tasktmp= line at all.
  cat > "$fake/state/$id.meta" <<META
window=fakeses:dj-$id
worktree=$TMP_ROOT/nonexistent-wt-$id
project=$TMP_ROOT/nonexistent-proj-$id
harness=claude
kind=ship
mode=no-mistakes
yolo=off
META
  DJ_HOME="$fake" bash "$fake/bin/dj-teardown.sh" "$id" >/dev/null 2>&1 \
    || fail "teardown exited non-zero when tasktmp= was absent"
  pass "dj-teardown skips gracefully when tasktmp= is absent (backward compat)"
}

test_teardown_skips_gracefully_when_dir_missing() {
  # tasktmp= points to a path that does not exist. Teardown must not error.
  local id=td-missing-z4
  local task_tmp="$TMP_ROOT/never-created-dj-$id"
  # Intentionally do NOT create $task_tmp.
  [ ! -e "$task_tmp" ] || fail "precondition: task_tmp should not exist yet"
  local fake
  fake=$(make_fake_root "$id" "$task_tmp")
  DJ_HOME="$fake" bash "$fake/bin/dj-teardown.sh" "$id" >/dev/null 2>&1 \
    || fail "teardown exited non-zero when tasktmp dir was missing"
  [ ! -e "$task_tmp" ] || fail "teardown created/left the tasktmp dir unexpectedly"
  pass "dj-teardown skips gracefully when tasktmp= points to a nonexistent dir"
}

test_teardown_removes_tasktmp_dir
test_teardown_skips_gracefully_without_tasktmp
test_teardown_skips_gracefully_when_dir_missing

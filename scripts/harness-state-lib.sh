#!/usr/bin/env bash
# Portable task-scoped state locks. Source after herdr-runtime-lib.sh.

state_process_identity() {
  local pid=$1 identity
  kill -0 "$pid" 2>/dev/null || return 0
  if [ -r "/proc/$pid/stat" ]; then
    awk '{print "proc:" $22}' "/proc/$pid/stat"
    return
  fi
  identity=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
  if [ -n "$identity" ]; then printf 'ps:%s\n' "$identity"; else printf 'live:%s\n' "$pid"; fi
}

state_lock_acquire() {
  local key=$1 lock owner pid identity observed
  require_fleet_mutation_allowed
  valid_task_id "$key" || die "invalid lock key: $key"
  lock="$HARNESS_STATE/locks/$key.lock"
  owner="$lock/owner.meta"
  mkdir -p "$HARNESS_STATE/locks"
  if ! mkdir "$lock" 2>/dev/null; then
    [ -f "$owner" ] && [ ! -L "$owner" ] || die "state lock is malformed: $lock"
    pid=$(meta_get "$owner" pid)
    identity=$(meta_get "$owner" identity)
    observed=$(state_process_identity "$pid")
    if [ -n "$observed" ] && [ "$observed" = "$identity" ]; then
      die "state is locked by live pid $pid: $key"
    fi
    rm "$owner"
    rmdir "$lock" || die "stale state lock contains unexpected files: $lock"
    mkdir "$lock" || die "could not acquire state lock: $key"
  fi
  STATE_LOCK_DIR=$lock
  identity=$(state_process_identity "$$")
  [ -n "$identity" ] || { rmdir "$lock"; die "could not identify lock owner process"; }
  printf 'pid=%s\nidentity=%s\nacquired_at=%s\n' \
    "$$" "$identity" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$owner"
  chmod 600 "$owner"
  trap state_lock_release EXIT HUP INT TERM
}

state_lock_release() {
  local lock=${STATE_LOCK_DIR:-}
  [ -n "$lock" ] || return 0
  if [ -f "$lock/owner.meta" ] && [ "$(meta_get "$lock/owner.meta" pid)" = "$$" ]; then
    rm "$lock/owner.meta"
    rmdir "$lock" 2>/dev/null || true
  fi
  STATE_LOCK_DIR=
  trap - EXIT HUP INT TERM
}

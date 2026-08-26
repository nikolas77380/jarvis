#!/usr/bin/env bash
# Enter away mode and run the sub-supervisor daemon in a harness-tracked
# foreground process when one is not already alive.
#
# Usage: dj-afk-start.sh
#   Sets state/.afk unless DJ_AFK_STATE_PREPARED=1, checks
#   state/.supervise-daemon.lock, and:
#     - prints "afk: daemon already running pid=<pid>" then exits 0 when that
#       lock is held by a live daemon (a REFRESH: no stale-artifact clear);
#     - otherwise clears any prior away session's stale escalation artifacts
#       (dj_afk_clear_stale_artifacts) for a direct, non-prepared start, then
#       execs bin/dj-supervise-daemon.sh in the foreground. A prepared start was
#       already cleared transactionally by bin/dj-afk-launch.sh.
#
# This file is sourceable: its BASH_SOURCE guard keeps main from running, while
# exposing the daemon-lock helpers and dj_afk_clear_stale_artifacts. Sourcing it
# enables nounset and errexit; callers that need different shell options must
# restore them explicitly.
#
# This is the COMMON daemon entry for every backend. HOW it becomes a tracked
# background process differs by harness/backend and is owned elsewhere:
#   - Harnesses with a native in-pane tracked-background tool (e.g. claude, grok)
#     run this directly via that tool, so the daemon inherits the captain pane's
#     env and auto-discovers it.
#   - Harnesses with NO native background mechanism (e.g. pi) run this THROUGH
#     bin/dj-afk-launch.sh, which creates a non-visible tracked terminal per
#     backend (herdr tab/workspace, tmux detached session) and passes the
#     captain pane in as DJ_SUPERVISOR_TARGET so injection targets it, not the
#     daemon's own new pane.
# Do not wrap this in `nohup ... &`: Codex/herdr can reap fire-and-forget shell
# children after the tool call returns, while a tracked background terminal stays
# attached and has a real lifecycle.
set -eu

DJ_AFK_START_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DJ_ROOT="${DJ_ROOT_OVERRIDE:-$(cd "$DJ_AFK_START_DIR/.." && pwd)}"
DJ_HOME="${DJ_HOME:-${DJ_ROOT_OVERRIDE:-$DJ_ROOT}}"
DJ_AFK_STATE="${DJ_STATE_OVERRIDE:-$DJ_HOME/state}"
DJ_AFK_LOCK="$DJ_AFK_STATE/.supervise-daemon.lock"
DJ_AFK_DAEMON="$DJ_AFK_START_DIR/dj-supervise-daemon.sh"

# shellcheck source=bin/dj-wake-lib.sh
. "$DJ_AFK_START_DIR/dj-wake-lib.sh"

dj_afk_start_usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# dj_afk_clear_stale_artifacts: on a FRESH away-session entry (the daemon is not
# already running), drop the previous away session's leftover escalation-delivery
# artifacts so they cannot surface as stale escalations under the new session.
# These are session-scoped by timing: a fresh entry owns a new supervision
# session and the new daemon has not produced anything yet, so anything present
# here belongs to a PRIOR session. This never drops a genuinely-pending
# escalation - the delivery buffer is a transient cache, and any condition still
# true (a crew still blocked, a check still firing) is re-derived and re-escalated
# fresh by the daemon's heartbeat catch-all scan and the durable
# state/.wake-queue replay (see docs/herdr-backend.md "Away-mode stale-artifact
# lifecycle" and bin/dj-supervise-daemon.sh's escalate_add/inject_wedge_alarm).
# NOT called on a refresh (daemon already alive), so the current session's own
# buffered escalations are preserved.
dj_afk_clear_stale_artifacts() {  # <state-dir>
  local state=$1
  rm -f "$state/.subsuper-escalations" \
        "$state/.subsuper-escalations.since" \
        "$state/.subsuper-inject-wedged" 2>/dev/null
}

daemon_lock_owner() {
  local owner
  if [ -L "$DJ_AFK_LOCK" ]; then
    owner=$(readlink "$DJ_AFK_LOCK" 2>/dev/null) || return 1
    [ -n "$owner" ] || return 1
    case "$owner" in
      /*) printf '%s\n' "$owner" ;;
      *) printf '%s/%s\n' "$(dirname "$DJ_AFK_LOCK")" "$owner" ;;
    esac
    return 0
  fi
  [ -d "$DJ_AFK_LOCK" ] || return 1
  printf '%s\n' "$DJ_AFK_LOCK"
}

daemon_pid_matches() {
  local pid=$1 owner=$2 identity current command
  identity=$(cat "$owner/pid-identity" 2>/dev/null || true)
  if [ -n "$identity" ]; then
    current=$(dj_pid_identity "$pid") || return 1
    [ "$current" = "$identity" ]
    return
  fi
  command=$(ps -p "$pid" -o command= 2>/dev/null || true)
  case "$command" in
    *"$DJ_AFK_DAEMON"*|*"dj-supervise-daemon.sh"*) return 0 ;;
  esac
  return 1
}

daemon_lock_pid() {
  local owner
  owner=$(daemon_lock_owner) || return 1
  cat "$owner/pid" 2>/dev/null || true
}

daemon_lock_held_by_live_daemon() {
  local owner pid
  owner=$(daemon_lock_owner) || return 1
  pid=$(cat "$owner/pid" 2>/dev/null || true)
  dj_pid_alive "$pid" || return 1
  daemon_pid_matches "$pid" "$owner"
}

dj_afk_flag_write() {  # <state-dir>
  local state=$1 lock="$1/.cursor-park-owner.lock" pending attempt=0 status=1
  mkdir -p "$state" || return 1
  [ ! -d "$state/.afk" ] || return 1
  pending=$(mktemp "$state/.afk.pending.XXXXXX") || return 1
  date '+%s' > "$pending" || { rm -f "$pending"; return 1; }
  while [ "$attempt" -lt 50 ]; do
    attempt=$((attempt + 1))
    if dj_lock_try_acquire "$lock"; then
      mv "$pending" "$state/.afk" && status=0
      dj_lock_release "$lock"
      rm -f "$pending" 2>/dev/null || true
      return "$status"
    fi
    [ "$attempt" -lt 50 ] && sleep 0.1
  done
  rm -f "$pending" 2>/dev/null || true
  return 1
}

dj_afk_start_main() {
  case "${1:-}" in
    '' ) ;;
    -h|--help) dj_afk_start_usage; return 0 ;;
    * ) echo "usage: $(basename "${BASH_SOURCE[1]:-dj-afk-start.sh}")" >&2; return 2 ;;
  esac

  mkdir -p "$DJ_AFK_STATE"
  if [ "${DJ_AFK_STATE_PREPARED:-0}" = 1 ]; then
    [ -f "$DJ_AFK_STATE/.afk" ] || { echo "afk: launcher-prepared state is missing" >&2; return 1; }
  else
    dj_afk_flag_write "$DJ_AFK_STATE" || { echo "afk: failed to write away-mode flag" >&2; return 1; }
  fi

  local pid
  pid=$(daemon_lock_pid 2>/dev/null || true)
  if daemon_lock_held_by_live_daemon; then
    echo "afk: daemon already running pid=$pid"
    return 0
  fi

  if dj_pid_alive "$pid" && [ -n "$pid" ]; then
    dj_lock_remove_path "$DJ_AFK_LOCK" 2>/dev/null || true
  fi

  # Fresh start: clear the previous away session's stale delivery artifacts
  # before the new daemon can surface them (fix for the leaked-artifact defect).
  if [ "${DJ_AFK_STATE_PREPARED:-0}" != 1 ]; then
    dj_afk_clear_stale_artifacts "$DJ_AFK_STATE"
  fi

  echo "afk: starting supervise daemon in foreground; keep this command as a tracked background session"
  exec "$DJ_AFK_DAEMON"
}

# Run only when executed, not when sourced (tests source dj_afk_clear_stale_artifacts
# and the lock helpers directly).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  dj_afk_start_main "$@"
fi

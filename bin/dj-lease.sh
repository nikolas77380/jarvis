#!/usr/bin/env bash
# dj-lease.sh - claim, release, inspect, and sweep per-task supervision leases.
#
# The lease contract itself (file format, actors, staleness, guard semantics)
# is owned by bin/dj-lease-lib.sh; this is the command surface the two
# supervision actors use around the overlap set (steering, stopping, cleanup,
# backlog status, stuck-worker recovery). "backlog" is the reserved resource
# the branch prompt claims around its own backlog writes; main's tasks-axi path
# is deliberately unguarded in this scope.
#
# Usage:
#   dj-lease.sh claim <task> [--actor main|branch]
#       Take the lease for the calling actor. Idempotent for the holder (the
#       claim refreshes its own lease). Refuses with exit 6 while the other
#       actor holds a live lease. A stale lease (dead pid, or a torn record)
#       is cleared and re-claimed.
#   dj-lease.sh release <task> [--actor main|branch]
#       Drop the calling actor's lease. Releasing a lease the actor does not
#       hold is a silent no-op, so a retry after a partial failure is safe.
#       Naming the other actor is refused loudly.
#   dj-lease.sh check <task>
#       Print "<actor> <pid> <epoch> <live|stale>" for a held lease, or
#       nothing (exit 1) when the task is unleased.
#   dj-lease.sh release-actor --actor main|branch
#       Drop every lease the named actor holds; the Pi branch extension runs
#       this at generation activation so a replaced branch conversation's
#       leases never outlive it.
#   dj-lease.sh sweep
#       Remove every provably stale lease in this home. Run at session start
#       (a lease held by a dead actor is cleared at session start); safe to
#       run any time - a live lease is never touched.
#
# The default actor is $DJ_SUPERVISION_ACTOR (else main); when --actor is
# supplied for a mutation, it must name that calling actor. Exit codes: 0 ok,
# 1 check-miss, 2 usage, 6 refused (other actor holds or actor mismatch).
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DJ_ROOT="${DJ_ROOT_OVERRIDE:-${DJ_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
DJ_HOME="${DJ_HOME:-${DJ_ROOT_OVERRIDE:-$DJ_ROOT}}"
STATE="${DJ_STATE_OVERRIDE:-$DJ_HOME/state}"
# shellcheck source=bin/dj-lease-lib.sh
. "$SCRIPT_DIR/dj-lease-lib.sh"
# shellcheck source=bin/dj-wake-lib.sh
. "$SCRIPT_DIR/dj-wake-lib.sh"

mkdir -p "$STATE"
LEASE_COMMAND_LOCK="$STATE/.dj-lease-command.lock"
dj_lock_acquire_wait "$LEASE_COMMAND_LOCK"
trap 'dj_lock_release "$LEASE_COMMAND_LOCK"' EXIT

usage() {
  echo "usage: dj-lease.sh claim|release <task> [--actor main|branch] | release-actor --actor main|branch | check <task> | sweep" >&2
  exit 2
}

CMD=${1:-}
shift 2>/dev/null || true

case "$CMD" in
  claim|release)
    TASK=${1:-}
    shift 2>/dev/null || true
    dj_lease_valid_id "$TASK" || usage
    ACTOR=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --actor)
          ACTOR=${2:-}
          shift 2 || usage
          ;;
        *) usage ;;
      esac
    done
    if [ -z "$ACTOR" ]; then
      ACTOR=$(dj_lease_actor) || exit 2
    fi
    case "$ACTOR" in main|branch) ;; *) usage ;; esac
    ;;
  check)
    TASK=${1:-}
    [ "$#" -le 1 ] || usage
    dj_lease_valid_id "$TASK" || usage
    ;;
  release-actor)
    ACTOR=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --actor)
          ACTOR=${2:-}
          shift 2 || usage
          ;;
        *) usage ;;
      esac
    done
    case "$ACTOR" in main|branch) ;; *) usage ;; esac
    ;;
  sweep)
    [ "$#" -eq 0 ] || usage
    ;;
  *) usage ;;
esac

case "$CMD" in
  claim)
    # Loud accidental-override guard: a claim naming the OTHER actor than the
    # caller's own injected identity is a wiring mistake, never a role change.
    # Release and bulk release enforce the same caller authorization below.
    CALLER=$(dj_lease_actor) || exit "$DJ_LEASE_REFUSE_EXIT"
    if [ "$ACTOR" != "$CALLER" ]; then
      echo "error: claim refused - the $CALLER supervision actor cannot claim a lease as $ACTOR on '$TASK'" >&2
      exit "$DJ_LEASE_REFUSE_EXIT"
    fi
    LEASE=$(dj_lease_path "$TASK")
    if dj_lease_live "$TASK" && [ "$DJ_LEASE_ACTOR" != "$ACTOR" ]; then
      echo "error: claim refused - task '$TASK' is leased to the $DJ_LEASE_ACTOR supervision actor (state/.lease-$TASK)" >&2
      exit "$DJ_LEASE_REFUSE_EXIT"
    fi
    # The lease outlives this CLI call, so its liveness pid must be the
    # long-lived supervising process: DJ_LEASE_HOLDER_PID when the caller
    # provides one (the Pi branch extension passes the session-lock holder),
    # else the session-lock holder (state/.lock is the harness pid), else this
    # shell; without a matching session lock the resulting lease is stale.
    HOLDER_PID=${DJ_LEASE_HOLDER_PID:-}
    case "$HOLDER_PID" in *[!0-9]*) HOLDER_PID= ;; esac
    if [ -z "$HOLDER_PID" ]; then
      HOLDER_PID=$(head -n 1 "$STATE/.lock" 2>/dev/null | tr -cd '0-9' || true)
    fi
    [ -n "$HOLDER_PID" ] || HOLDER_PID=$$
    TMP=$(mktemp "$STATE/.dj-lease-tmp.XXXXXX")
    printf '%s\t%s\t%s\n' "$ACTOR" "$HOLDER_PID" "$(date +%s)" > "$TMP"
    if [ -e "$LEASE" ]; then
      # Same-actor refresh, or a stale/torn record: replace atomically.
      mv -f -- "$TMP" "$LEASE"
    elif ! ln -- "$TMP" "$LEASE" 2>/dev/null; then
      # Lost the create race to the sibling actor; re-check who won.
      rm -f -- "$TMP"
      if dj_lease_live "$TASK" && [ "$DJ_LEASE_ACTOR" != "$ACTOR" ]; then
        echo "error: claim refused - task '$TASK' was just leased to the $DJ_LEASE_ACTOR supervision actor" >&2
        exit "$DJ_LEASE_REFUSE_EXIT"
      fi
      TMP=$(mktemp "$STATE/.dj-lease-tmp.XXXXXX")
      printf '%s\t%s\t%s\n' "$ACTOR" "$HOLDER_PID" "$(date +%s)" > "$TMP"
      mv -f -- "$TMP" "$LEASE"
    else
      rm -f -- "$TMP"
    fi
    ;;
  release)
    CALLER=$(dj_lease_actor) || exit "$DJ_LEASE_REFUSE_EXIT"
    if [ "$ACTOR" != "$CALLER" ]; then
      echo "error: release refused - the $CALLER supervision actor cannot release a lease as $ACTOR on '$TASK'" >&2
      exit "$DJ_LEASE_REFUSE_EXIT"
    fi
    if dj_lease_read "$TASK" && { [ "$DJ_LEASE_ACTOR" = "$ACTOR" ] || [ -z "$DJ_LEASE_ACTOR" ]; }; then
      rm -f -- "$(dj_lease_path "$TASK")"
    fi
    ;;
  check)
    dj_lease_read "$TASK" || exit 1
    if dj_lease_live "$TASK"; then LIVENESS=live; else LIVENESS=stale; fi
    printf '%s %s %s %s\n' "${DJ_LEASE_ACTOR:-unreadable}" "${DJ_LEASE_PID:-0}" "${DJ_LEASE_EPOCH:-0}" "$LIVENESS"
    ;;
  release-actor)
    CALLER=$(dj_lease_actor) || exit "$DJ_LEASE_REFUSE_EXIT"
    if [ "$ACTOR" != "$CALLER" ]; then
      echo "error: release-actor refused - the $CALLER supervision actor cannot release leases as $ACTOR" >&2
      exit "$DJ_LEASE_REFUSE_EXIT"
    fi
    for LEASE in "$STATE"/.lease-*; do
      [ -e "$LEASE" ] || continue
      case "$LEASE" in *.lock) continue ;; esac
      TASK=${LEASE##*/.lease-}
      dj_lease_valid_id "$TASK" || continue
      if dj_lease_read "$TASK" && [ "$DJ_LEASE_ACTOR" = "$ACTOR" ]; then
        rm -f -- "$LEASE"
      fi
    done
    ;;
  sweep)
    for LEASE in "$STATE"/.lease-*; do
      [ -e "$LEASE" ] || continue
      case "$LEASE" in *.lock) continue ;; esac
      TASK=${LEASE##*/.lease-}
      dj_lease_valid_id "$TASK" || continue
      dj_lease_clear_stale "$TASK"
    done
    ;;
esac

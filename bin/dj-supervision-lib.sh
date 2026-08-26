# shellcheck shell=bash
# Shared "supervision missing" predicate.
# Usage: . bin/dj-supervision-lib.sh
#
# Reports whether a jarvis home needs supervision because it has in-flight
# work (a state/<id>.meta exists) or an X-mode relay poll
# (state/x-watch.check.sh), and whether its watcher has a fresh liveness beacon
# (state/.last-watcher-beat, touched every poll cycle, within the grace window).
# bin/dj-turnend-guard.sh uses the PID-strict dj_watcher_healthy from
# bin/dj-wake-lib.sh for its block decision. bin/dj-guard.sh uses the model-aware
# dj_watcher_supervision_verdict (also in bin/dj-wake-lib.sh), which owns what a
# live watcher process means per supervision model. The status fields here retain
# the beacon-age details used in their messages.

# Portable mtime; Linux stat lacks -f, macOS stat lacks -c.
dj_sup_stat_mtime() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %m "$1" 2>/dev/null
  else
    stat -c %Y "$1" 2>/dev/null
  fi
}

# dj_supervision_status <state-dir> [grace-seconds]
# Populates, for the state dir at $1:
#   DJ_SUP_IN_FLIGHT      count of state/*.meta (in-flight tasks)
#   DJ_SUP_SOURCES        count of registered process-to-event sources
#   DJ_SUP_NEEDED         true/false - in-flight work, an X-mode relay poll, or a
#                         registered event source (a source is a wait on an
#                         external process, not a task, so it has no metadata)
#   DJ_SUP_WATCHER_FRESH  true/false - a watcher beacon within the grace window
#   DJ_SUP_BEACON_DESC    human-readable beacon age, for banners ("never" if absent)
#   DJ_SUP_QUEUE_PENDING  true/false - state/.wake-queue has unread records
# grace-seconds defaults to $DJ_GUARD_GRACE, then 300, matching dj-guard.sh.
# Always returns 0; callers read the vars, or use dj_supervision_unhealthy below.
dj_supervision_status() {
  local state=$1 grace=${2:-${DJ_GUARD_GRACE:-300}} meta source beat m age
  DJ_SUP_IN_FLIGHT=0
  DJ_SUP_NEEDED=false
  DJ_SUP_WATCHER_FRESH=false
  DJ_SUP_BEACON_DESC=never
  DJ_SUP_QUEUE_PENDING=false

  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    DJ_SUP_IN_FLIGHT=$((DJ_SUP_IN_FLIGHT + 1))
  done
  DJ_SUP_SOURCES=0
  for source in "$state"/procevent/*.source; do
    [ -e "$source" ] || continue
    DJ_SUP_SOURCES=$((DJ_SUP_SOURCES + 1))
  done
  if [ "$DJ_SUP_IN_FLIGHT" -gt 0 ] \
    || [ -f "$state/x-watch.check.sh" ] \
    || [ "$DJ_SUP_SOURCES" -gt 0 ]; then
    DJ_SUP_NEEDED=true
  fi

  beat="$state/.last-watcher-beat"
  if [ -e "$beat" ]; then
    m=$(dj_sup_stat_mtime "$beat")
    if [ -n "$m" ]; then
      age=$(( $(date +%s) - m ))
      DJ_SUP_BEACON_DESC="${age}s ago"
      [ "$age" -lt "$grace" ] && DJ_SUP_WATCHER_FRESH=true
    else
      # shellcheck disable=SC2034 # Read by callers (dj-guard.sh) after sourcing.
      DJ_SUP_BEACON_DESC=unknown
    fi
  fi

  # shellcheck disable=SC2034 # Read by callers (dj-guard.sh) after sourcing.
  [ -s "$state/.wake-queue" ] && DJ_SUP_QUEUE_PENDING=true
  return 0
}

# dj_supervision_needed <state-dir> [grace-seconds]
# Exit 0 (true) exactly when the home needs a watcher.
dj_supervision_needed() {
  dj_supervision_status "$@"
  [ "$DJ_SUP_NEEDED" = true ]
}

# dj_supervision_unhealthy <state-dir> [grace-seconds]
# Exit 0 (true) exactly when supervision is needed and no watcher has a fresh
# beacon. Exit 1 (false) otherwise.
dj_supervision_unhealthy() {
  dj_supervision_status "$@"
  [ "$DJ_SUP_NEEDED" = true ] && [ "$DJ_SUP_WATCHER_FRESH" = false ]
}

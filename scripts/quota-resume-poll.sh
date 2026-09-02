#!/usr/bin/env bash
# Observe quota-blocked agents and resume any whose provider reset time has arrived.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
. "$HARNESS_ROOT/scripts/quota-resume-lib.sh"

require_tools
NOW=$(date +%s)

quota_observe() {
  local key=$1 kind=$2 meta=$3 name session engine state output epoch
  [ ! -f "$HARNESS_STATE/quota/$key.meta" ] || return 0
  [ -f "$meta" ] && [ ! -L "$meta" ] || return 0
  [ "$(meta_get "$meta" stopped)" != 1 ] || return 0
  name=$(meta_get "$meta" agent_name); session=$(meta_get "$meta" session); engine=$(meta_get "$meta" engine)
  [ -n "$name" ] && [ -n "$session" ] || return 0
  state=$(agent_status "$name" "$session")
  case "$state" in idle|done|blocked) ;; *) return 0 ;; esac
  output=$(herdr --session "$session" agent read "$name" --source recent-unwrapped --lines 120 2>/dev/null || true)
  printf '%s\n' "$output" | quota_message_matches || return 0
  epoch=$(quota_resume_epoch "$output") || return 0
  quota_meta_write "$key" "$kind" "$engine" "$epoch" "$output" >/dev/null
}

JARVIS_META="$HARNESS_STATE/jarvis.meta"
quota_observe jarvis jarvis "$JARVIS_META"
for META in "$HARNESS_STATE"/*.meta; do
  [ -f "$META" ] || continue
  [ "$(meta_get "$META" schema)" = harness-herdr-task.v1 ] || continue
  quota_observe "$(meta_get "$META" task)" task "$META"
done

for QUOTA in "$HARNESS_STATE"/quota/*.meta; do
  [ -f "$QUOTA" ] || continue
  EPOCH=$(meta_get "$QUOTA" resume_at)
  case "$EPOCH" in ''|*[!0-9]*) continue ;; esac
  [ "$EPOCH" -le "$NOW" ] || continue
  KEY=$(meta_get "$QUOTA" key); KIND=$(meta_get "$QUOTA" kind); ENGINE=$(meta_get "$QUOTA" engine)
  case "$KIND" in
    task) "$HARNESS_ROOT/scripts/agent-switch.sh" "$KEY" "$ENGINE" --relaunch --note "Provider quota reset. Resume automatically from the preserved task state." >/dev/null ;;
    jarvis) JARVIS_NO_ATTACH=1 "$HARNESS_ROOT/bin/jarvis" relaunch >/dev/null ;;
    *) continue ;;
  esac
  quota_meta_remove "$KEY"
  printf 'quota resumed: %s\n' "$KEY"
done

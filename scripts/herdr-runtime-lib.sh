#!/usr/bin/env bash
# Shared mechanics for the harness's single Herdr runtime.

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_STATE="${HARNESS_STATE_DIR:-$HARNESS_ROOT/.harness-state}"
HARNESS_WORKTREES="${HARNESS_WORKTREE_DIR:-$HARNESS_ROOT/.harness-worktrees}"
HARNESS_HERDR_SESSION="${HARNESS_HERDR_SESSION:-harness}"
export HARNESS_ROOT HARNESS_STATE HARNESS_WORKTREES HARNESS_HERDR_SESSION

die() { echo "error: $*" >&2; exit 1; }

require_tools() {
  command -v herdr >/dev/null 2>&1 || die "herdr is required"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  command -v git >/dev/null 2>&1 || die "git is required"
}

valid_task_id() {
  case "$1" in ''|*[!a-zA-Z0-9._-]*) return 1 ;; esac
  [ "${#1}" -le 96 ]
}

task_card() {
  local id=$1 card count
  count=$(find "$HARNESS_ROOT/plan" -maxdepth 1 -type f -name "$id*.md" ! -name 'TEMPLATE.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" = 1 ] || die "expected exactly one plan card for $id, found $count"
  card=$(find "$HARNESS_ROOT/plan" -maxdepth 1 -type f -name "$id*.md" ! -name 'TEMPLATE.md' -print)
  printf '%s\n' "$card"
}

task_meta() {
  valid_task_id "$1" || die "invalid task id: $1"
  printf '%s/%s.meta\n' "$HARNESS_STATE" "$1"
}

meta_get() {
  local file=$1 key=$2
  sed -n "s/^${key}=//p" "$file" | tail -1
}

require_meta() {
  local file
  file=$(task_meta "$1")
  [ -f "$file" ] && [ ! -L "$file" ] || die "runtime metadata not found for $1"
  [ "$(meta_get "$file" schema)" = harness-herdr-task.v1 ] \
    || die "runtime metadata has an unsupported or missing schema: $file"
  printf '%s\n' "$file"
}

herdr_call() {
  herdr --session "$HARNESS_HERDR_SESSION" "$@"
}

workspace_ensure() {
  local record="$HARNESS_STATE/herdr-workspace.meta" out workspace tmp
  mkdir -p "$HARNESS_STATE"
  if [ -f "$record" ] && [ ! -L "$record" ]; then
    [ "$(meta_get "$record" session)" = "$HARNESS_HERDR_SESSION" ] \
      || die "recorded Herdr workspace belongs to another session; set HARNESS_HERDR_SESSION or reconcile $record"
    workspace=$(meta_get "$record" workspace)
    [ -n "$workspace" ] && { printf '%s\n' "$workspace"; return; }
  fi
  out=$(herdr_call workspace create --cwd "$HARNESS_ROOT" --label harness --no-focus) \
    || die "could not create the harness Herdr workspace"
  workspace=$(printf '%s' "$out" | jq -er '.result.workspace.workspace_id') \
    || die "could not read workspace id from Herdr"
  tmp=$(mktemp "$HARNESS_STATE/.workspace.XXXXXX")
  printf 'session=%s\nworkspace=%s\n' "$HARNESS_HERDR_SESSION" "$workspace" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$record"
  printf '%s\n' "$workspace"
}

agent_runtime_name() {
  local id=$1 safe sum
  safe=$(printf '%s' "$id" | tr '[:upper:].-' '[:lower:]__' | cut -c1-22)
  sum=$(printf '%s' "$id" | cksum | awk '{print $1}' | cut -c1-7)
  printf 'h_%s_%s\n' "$safe" "$sum"
}

card_brief() {
  awk '
    /^## Brief([[:space:]]|$)/ {inside=1; next}
    inside && /^## / {exit}
    inside {print}
  ' "$1" | sed '/./,$!d'
}

card_field() {
  local card=$1 field=$2
  sed -n -E "s/.*\\*\\*${field}:\\*\\*[[:space:]]*([^·[:space:]]+).*/\\1/p" "$card" | head -1
}

role_field() {
  local role=$1 field=$2
  awk -F: -v key="$field" '
    $1 == key {
      value=substr($0, index($0, ":") + 1)
      gsub(/^[[:space:]\"]+|[[:space:]\"]+$/, "", value)
      print value
      exit
    }
  ' "$role"
}

atomic_meta_write() {
  local destination=$1 tmp
  mkdir -p "$HARNESS_STATE"
  tmp=$(mktemp "$HARNESS_STATE/.task-meta.XXXXXX")
  cat > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$destination"
}

agent_status() {
  local name=$1 session=${2:-$HARNESS_HERDR_SESSION} out status
  out=$(herdr --session "$session" agent get "$name" 2>/dev/null) || { printf 'unknown'; return; }
  status=$(printf '%s' "$out" | jq -r '.result.agent.agent_status // "unknown"' 2>/dev/null) || status=unknown
  case "$status" in working|idle|done|blocked) printf '%s' "$status" ;; *) printf 'unknown' ;; esac
}

#!/usr/bin/env bash
# Shared mechanics for the harness's single Herdr runtime.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IS_JARVIS_LINKED_WORKTREE=false
JARVIS_LINKED_WORKTREE_PATH=""
# A root-project (reserved id `jarvis`) task worktree is a linked worktree that carries the
# harness's own scripts/, so the BASH_SOURCE-derived root above would otherwise resolve to the
# worktree itself instead of the main checkout — silently forking a second fleet (its own
# .harness-worktrees/.harness-state, invisible to the real runtime).
#
# `.git` is a file rather than a directory for BOTH a linked worktree and a submodule checkout, so
# that alone does not distinguish them — treating a submodule as a linked worktree once resolved
# `HARNESS_ROOT` into `<super>/.git/modules/<name>`, a path that is not a checkout at all. The
# distinguishing property: a linked worktree's `--git-dir` (its own `.git/worktrees/<name>`) differs
# from its `--git-common-dir` (the main checkout's `.git`); a submodule's git-dir and common-dir are
# the same path (it owns its own history, not a linked view of another). Only the worktree shape is
# re-resolved; a submodule is left as an ordinary standalone checkout.
if [ -f "$HARNESS_ROOT/.git" ]; then
  GIT_DIR=$(git -C "$HARNESS_ROOT" rev-parse --path-format=absolute --git-dir 2>/dev/null) || GIT_DIR=""
  GIT_COMMON_DIR=$(git -C "$HARNESS_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || GIT_COMMON_DIR=""
  if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON_DIR" ] && [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
    CANDIDATE_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd)"
    # Sanity-check the resolved path is actually a harness checkout before trusting it — a linked
    # worktree of some other repository that happens to nest under this one is not our concern, and
    # must never be silently adopted as HARNESS_ROOT.
    if [ -f "$CANDIDATE_ROOT/scripts/herdr-runtime-lib.sh" ]; then
      IS_JARVIS_LINKED_WORKTREE=true
      JARVIS_LINKED_WORKTREE_PATH="$HARNESS_ROOT"
      HARNESS_ROOT="$CANDIDATE_ROOT"
    fi
  fi
  unset GIT_DIR GIT_COMMON_DIR CANDIDATE_ROOT
fi
HARNESS_STATE="${HARNESS_STATE_DIR:-$HARNESS_ROOT/.harness-state}"
HARNESS_WORKTREES="${HARNESS_WORKTREE_DIR:-$HARNESS_ROOT/.harness-worktrees}"
HARNESS_HERDR_SESSION="${HARNESS_HERDR_SESSION:-harness}"
export HARNESS_ROOT HARNESS_STATE HARNESS_WORKTREES HARNESS_HERDR_SESSION IS_JARVIS_LINKED_WORKTREE JARVIS_LINKED_WORKTREE_PATH

# The lead operates the fleet only from the canonical checkout; a specialist working in its own
# linked Jarvis task worktree must never fork a second fleet from there. Every entry point that
# mutates shared runtime state (worktrees, Herdr tabs, task metadata, the inbox/decisions ledgers)
# calls this before doing so — see state_lock_acquire in harness-state-lib.sh, the single choke
# point all of them already pass through. Read-only inspection (task_card, plan_card_matches,
# project_root_path, and every script that only reads them) is unaffected: it is meant to work from
# a linked worktree, resolving against the same canonical state a lead session would see.
require_fleet_mutation_allowed() {
  [ "$IS_JARVIS_LINKED_WORKTREE" = false ] \
    || die "refusing to mutate the fleet from a linked Jarvis task worktree ($JARVIS_LINKED_WORKTREE_PATH) — run this from the canonical checkout at $HARNESS_ROOT instead"
}

require_tools() {
  command -v herdr >/dev/null 2>&1 || die "herdr is required"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  command -v git >/dev/null 2>&1 || die "git is required"
}

valid_task_id() {
  case "$1" in ''|*[!a-zA-Z0-9._-]*) return 1 ;; esac
  [ "${#1}" -le 96 ]
}

# Reserved project id: the harness root checkout itself, so Jarvis can dispatch work against its own
# runtime through the same plan/worktree/review pipeline nested projects use, without a permanent
# self-clone under projects/. A nested projects/jarvis would physically collide with this reserved
# id, so it is refused rather than silently misread (see card_project).
JARVIS_ROOT_PROJECT_ID=jarvis

# The one resolver for a project id's physical checkout path. Every caller that needs a project's
# location (role/worktree resolution, plan discovery, onboarding) MUST go through this — never test
# `[ "$project" = jarvis ]` inline, so the root case can't drift out of sync between callers.
project_root_path() {
  local project=$1
  if [ "$project" = "$JARVIS_ROOT_PROJECT_ID" ]; then
    printf '%s\n' "$HARNESS_ROOT"
  else
    printf '%s\n' "$HARNESS_ROOT/projects/$project"
  fi
}

# Plan cards live per-project, under projects/<project>/plan/, plus the reserved root project's own
# plan/ directly under the harness root (project_root_path's one exception) — never any other shared
# plan/. Each project brings its own plan/claims/review-rounds machinery scoped to its own git repo
# and worktrees, so a card's location is what tells us which project it belongs to.
plan_card_matches() {
  local id=$1
  if [ -d "$HARNESS_ROOT/plan" ]; then
    find "$HARNESS_ROOT/plan" -mindepth 1 -maxdepth 1 -type f -name "$id*.md" ! -name 'TEMPLATE.md' 2>/dev/null || true
  fi
  find "$HARNESS_ROOT/projects" -mindepth 3 -maxdepth 3 -type f -path '*/plan/*' -name "$id*.md" ! -name 'TEMPLATE.md' 2>/dev/null || true
}

task_card() {
  local id=$1 card count
  count=$(plan_card_matches "$id" | wc -l | tr -d ' ')
  [ "$count" = 1 ] || die "expected exactly one plan card for $id, found $count"
  card=$(plan_card_matches "$id")
  printf '%s\n' "$card"
}

card_project() {
  local card=$1 rel project
  case "$card" in
    "$HARNESS_ROOT/plan/"*) printf '%s\n' "$JARVIS_ROOT_PROJECT_ID"; return ;;
    "$HARNESS_ROOT/projects/"*) rel=${card#"$HARNESS_ROOT/projects/"} ;;
    *) die "plan card is not under projects/<project>/plan or the root plan/: $card" ;;
  esac
  project=${rel%%/*}
  [ -n "$project" ] && [ "$project" != "$rel" ] || die "could not derive project from card path: $card"
  [ "$project" != "$JARVIS_ROOT_PROJECT_ID" ] \
    || die "project id '$JARVIS_ROOT_PROJECT_ID' is reserved for the harness root — projects/$JARVIS_ROOT_PROJECT_ID collides with it: $card"
  printf '%s\n' "$project"
}

# Two different projects can both instantiate a stack-named role (e.g. nextjs-engineer) with
# genuinely different content — different app path, different rules. A project-local role always
# wins over the harness-shared one, so it is never possible for one project's role file to shadow
# another's. For the reserved root project this collapses to the harness's own agents/ on both legs.
role_path() {
  local project=$1 agent=$2 role
  role="$(project_root_path "$project")/agents/$agent.md"
  [ -f "$role" ] || role="$HARNESS_ROOT/agents/$agent.md"
  printf '%s\n' "$role"
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

# A codex-engine tab stamps its own pane with an isolated HOME/CODEX_HOME (below) that outlives the
# agent process — running any harness command from that same pane later must not treat the isolated
# home as real. Resolve the OS user record instead of trusting a possibly-poisoned $HOME.
real_user_home() {
  local home
  if command -v dscl >/dev/null 2>&1; then
    home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $NF}')
  fi
  if [ -z "${home:-}" ] && command -v getent >/dev/null 2>&1; then
    home=$(getent passwd "$(id -un)" | cut -d: -f6)
  fi
  printf '%s\n' "${home:-$HOME}"
}

codex_isolated_environment() {
  local key=$1 project_root=$2
  local runtime_home="$HARNESS_STATE/codex-homes/$1/home" runtime_state="$HARNESS_STATE/codex-homes/$1/state"
  local source_state auth config extra_config tmp real_home
  real_home=$HOME
  case "$real_home" in "$HARNESS_STATE/codex-homes/"*) real_home=$(real_user_home) ;; esac
  source_state=${CODEX_HOME:-$real_home/.codex}
  case "$source_state" in "$HARNESS_STATE/codex-homes/"*) source_state="$real_home/.codex" ;; esac
  auth="$source_state/auth.json"
  [ -f "$auth" ] || die "Codex authentication not found at $auth; run codex login first"
  case "$real_home$project_root" in *\"*) die 'paths containing double quotes are unsupported for the isolated Codex environment' ;; esac
  mkdir -p "$runtime_home" "$runtime_state"
  if [ -e "$runtime_state/auth.json" ] || [ -L "$runtime_state/auth.json" ]; then
    [ -L "$runtime_state/auth.json" ] && [ "$(readlink "$runtime_state/auth.json")" = "$auth" ] \
      || die "unexpected Codex auth file at $runtime_state/auth.json"
  else
    ln -s "$auth" "$runtime_state/auth.json"
  fi
  config="$runtime_state/config.toml"
  tmp=$(mktemp "$runtime_state/.config.XXXXXX")
  printf '[features]\nplugins = false\nskill_search = false\n\n[projects."%s"]\ntrust_level = "trusted"\n\n[shell_environment_policy]\ninherit = "all"\n\n[shell_environment_policy.set]\nHOME = "%s"\n' \
    "$project_root" "$real_home" > "$tmp"
  extra_config="$HARNESS_ROOT/config/jarvis-codex.toml"
  if [ "$key" = jarvis ] && [ -f "$extra_config" ]; then
    printf '\n' >> "$tmp"
    cat "$extra_config" >> "$tmp"
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$config"
  printf '%s\n%s\n' "$runtime_home" "$runtime_state"
}

workspace_ensure() {
  local record="$HARNESS_STATE/herdr-workspace.meta" out workspace tmp
  require_fleet_mutation_allowed
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
  require_fleet_mutation_allowed
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

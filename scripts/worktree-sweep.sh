#!/usr/bin/env bash
# Reclaim agent worktrees that are finished with, and say out loud why it refused the rest.
#
# WHY A SWEEP AND NOT A LIFECYCLE HOOK. task-teardown.sh already removes the worktree of a task that
# reached the end of the pipeline - card done, agent stopped, Clean Slate evidence archived, branch
# published. That is the right gate for the happy path and this script does not replace it. But every
# worktree that leaked did so precisely because it never reached that gate: an agent that died
# without reporting, a card abandoned mid-round, a session that crashed, and - the largest group
# measured 2026-09-23 - worktrees under `<repo>/.claude/worktrees/` and `~/.treehouse/` that
# agent-spawn.sh never created and no harness hook will ever fire for. 36 copies, ~45 GB, 17 of them
# more than three weeks old.
#   - On agent completion is too EARLY: agent-review.sh deliberately reuses the same worktree for
#     every reviewer and fix round of a task, and the lead reads the run's evidence out of it after
#     the agent is gone.
#   - On card close or on PR merge catches only the path task-teardown.sh already covers, and not one
#     of the leaked copies ever got there.
#   - A sweep is the only thing that can see a directory whose owner is dead, or that the harness
#     never recorded at all. So the sweep is the mechanism, and the age threshold plus the live
#     checks in worktree-reclaim-lib.sh are what keep it from being early.
#
# Dry run by default. Nothing is ever removed without --execute, no branch is ever deleted, and the
# verdict for every single candidate is printed whichever mode you run in.
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
# shellcheck source=scripts/worktree-reclaim-lib.sh
. "$HARNESS_ROOT/scripts/worktree-reclaim-lib.sh"

USAGE='usage: worktree-sweep.sh [--execute] [--older-than <days>] [--root <path>]... [--rescue <dir>] [--json]\n       --root replaces the default set of roots; repeat it to sweep several'
EXECUTE=false
THRESHOLD=7
JSON=false
RESCUE=''
SIZES=true
MODE=full
EXTRA_ROOTS=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --execute) EXECUTE=true; shift ;;
    --json) JSON=true; shift ;;
    --no-size) SIZES=false; shift ;;
    --quick) MODE=quick; SIZES=false; shift ;;
    --older-than) [ "$#" -ge 2 ] || die "$USAGE"; THRESHOLD=$2; shift 2 ;;
    --root) [ "$#" -ge 2 ] || die "$USAGE"; EXTRA_ROOTS="$EXTRA_ROOTS$2"$'\n'; shift 2 ;;
    --rescue) [ "$#" -ge 2 ] || die "$USAGE"; RESCUE=$2; shift 2 ;;
    *) die "$USAGE" ;;
  esac
done
case "$THRESHOLD" in ''|*[!0-9]*) die "--older-than takes a whole number of days, got: $THRESHOLD" ;; esac
command -v git >/dev/null 2>&1 || die 'git is required'
command -v jq >/dev/null 2>&1 || die 'jq is required'
# Removing a worktree is fleet mutation: refuse it from inside a linked Jarvis task worktree,
# the same choke point every other mutating entry point passes through.
[ "$EXECUTE" = false ] || require_fleet_mutation_allowed
[ "$EXECUTE" = false ] || [ "$MODE" = full ] || die '--quick never removes anything; drop it to use --execute'

# Every place an agent worktree is known to appear. The first is the harness's own; the rest belong
# to tools the harness does not drive - Claude Code's own `EnterWorktree` writes into
# `<repo>/.claude/worktrees/`, treehouse into `~/.treehouse/` - which is exactly why nothing was ever
# cleaning them up. A project can add its own with `worktreeSweepRoots` in config/harness.json.
#
# `--root` REPLACES this list rather than extending it: pointing the sweep somewhere specific should
# mean only there, so that aiming it at one directory can never reach a second one by surprise.
sweep_roots() {
  local base
  if [ -n "$EXTRA_ROOTS" ]; then
    printf '%s' "$EXTRA_ROOTS"
    return
  fi
  printf '%s\n' "$HARNESS_WORKTREES"
  for base in "$HARNESS_ROOT" "$HARNESS_ROOT"/projects/*; do
    [ -d "$base" ] || continue
    printf '%s/.claude/worktrees\n' "$base"
  done
  printf '%s/.treehouse\n' "$(real_user_home)"
  if [ -f "$HARNESS_ROOT/config/harness.json" ]; then
    jq -r '.worktreeSweepRoots // [] | .[]' "$HARNESS_ROOT/config/harness.json" 2>/dev/null || true
  fi
}

# Walk a root looking for worktree ROOTS, and stop descending the moment one is found - a worktree's
# own subdirectories are never separate candidates, and descending into a node_modules to prove it
# would cost more than the sweep saves.
discover() {
  local dir=$1 depth=$2 child
  [ -d "$dir" ] || return 0
  [ "$depth" -gt 0 ] || return 0
  for child in "$dir"/*; do
    [ -d "$child" ] || continue
    [ ! -L "$child" ] || continue
    if [ -e "$child/.git" ]; then
      printf '%s\n' "$child"
    else
      discover "$child" "$((depth - 1))"
    fi
  done
}

CANDIDATES=$(mktemp)
RESULTS=$(mktemp)
trap 'rm -f "$CANDIDATES" "$RESULTS"; worktree_reclaim_release' EXIT
while IFS= read -r ROOT; do
  [ -n "$ROOT" ] || continue
  # A root that is itself a worktree is the candidate, not a directory to look inside: `--root
  # <one worktree>` is how a person inspects or reclaims exactly one.
  if [ -d "$ROOT" ] && [ -e "$ROOT/.git" ]; then
    printf '%s\n' "$ROOT" >> "$CANDIDATES"
  else
    discover "$ROOT" 3 >> "$CANDIDATES"
  fi
done < <(sweep_roots)
sort -u "$CANDIDATES" -o "$CANDIDATES"

# Rescue the one blocker class that is content rather than history: files nobody ever added to git.
# Copied out with their relative paths intact, verified by count, and only then does the worktree
# become removable. Opt-in, and never applied to modified tracked files or unpushed commits - those
# live in git's own object model and a copy is not an equivalent record of them.
rescue_untracked() {
  local path=$1 slug target file copied listed
  slug=$(printf '%s' "${path#/}" | tr '/' '-')
  target="$RESCUE/$slug-$(date -u '+%Y%m%dT%H%M%SZ')"
  mkdir -p "$target" || return 1
  listed=0; copied=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    listed=$((listed + 1))
    mkdir -p "$target/$(dirname "$file")" || return 1
    cp -p "$path/$file" "$target/$file" || return 1
    [ -s "$target/$file" ] || [ ! -s "$path/$file" ] || return 1
    copied=$((copied + 1))
  done < <(worktree_reclaim_untracked "$path")
  [ "$listed" = "$copied" ] || return 1
  # Only once every file is copied and verified does the original go. Leaving them in place would
  # make the worktree un-removable anyway, and moving in two steps means a failure halfway through
  # leaves the content in at least one of the two places rather than neither.
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rm -f "$path/$file" || return 1
  done < <(worktree_reclaim_untracked "$path")
  printf '%s\n' "$target"
}

worktree_reclaim_prime
while IFS= read -r WT; do
  [ -n "$WT" ] || continue
  OBS=$(WORKTREE_RECLAIM_SIZES="$SIZES" worktree_reclaim_inspect "$WT" "$THRESHOLD" "$MODE")
  RESCUED=''
  if [ -n "$RESCUE" ] \
    && [ "$(printf '%s' "$OBS" | jq -r '[.blockers[].kind] | unique | join(",")')" = untracked-files ]; then
    if RESCUED=$(rescue_untracked "$WT"); then
      OBS=$(printf '%s' "$OBS" | jq --arg r "$RESCUED" '.blockers = [] | .reclaimable = true | .rescuedTo = $r')
    else
      RESCUED=''
      OBS=$(printf '%s' "$OBS" | jq '.blockers += [{kind:"rescue-failed",detail:"untracked files could not be copied out; nothing was removed"}] | .reclaimable = false')
    fi
  fi
  ACTION=skipped
  if [ "$(printf '%s' "$OBS" | jq -r '.reclaimable')" = true ]; then
    if [ "$EXECUTE" = true ]; then
      REPO=$(printf '%s' "$OBS" | jq -r '.repo')
      if git -C "$REPO" worktree remove "$WT" 2>/dev/null; then
        ACTION=removed
      else
        ACTION=remove-failed
        OBS=$(printf '%s' "$OBS" | jq '.blockers += [{kind:"remove-failed",detail:"git worktree remove refused; the worktree may be locked - inspect it by hand"}] | .reclaimable = false')
      fi
    else
      ACTION=reclaimable
    fi
  fi
  printf '%s' "$OBS" | jq -c --arg action "$ACTION" '.action = $action' >> "$RESULTS"
done < "$CANDIDATES"

SUMMARY=$(jq -s --argjson threshold "$THRESHOLD" --arg mode "$MODE" \
  --argjson executed "$([ "$EXECUTE" = true ] && echo true || echo false)" \
  '{schema:"harness-worktree-sweep.v1",thresholdDays:$threshold,mode:$mode,executed:$executed,
    scanned:length,
    removed:[.[]|select(.action=="removed")]|length,
    reclaimableBytes:([.[]|select(.action=="removed" or .action=="reclaimable")|.sizeBytes]|add // 0),
    refused:[.[]|select(.reclaimable|not)]|length,
    pastThreshold:[.[]|select([.blockers[].kind]|index("recently-active")|not)]|length,
    worktrees:.}' "$RESULTS")

if [ "$JSON" = true ]; then
  printf '%s\n' "$SUMMARY"
  exit 0
fi

printf '%s' "$SUMMARY" | jq -r '
  def gb: . / 1073741824 * 10 | round / 10 | tostring;
  if .mode == "quick" then
    "worktree sweep (quick): \(.scanned) agent worktree(s), \(.pastThreshold) past the \(.thresholdDays)-day threshold · run scripts/worktree-sweep.sh for a verdict on each"
  else
  "worktree sweep: scanned \(.scanned) · threshold \(.thresholdDays)d · " +
  (if .executed then "removed \(.removed)" else "reclaimable \(.scanned - .refused)" end) +
  " · \(.reclaimableBytes|gb) GB (du) · refused \(.refused)" end,
  "",
  (select(.mode != "quick") | .worktrees[] |
    "\(.action)\t\(.ageDays)d\t\(.sizeBytes / 1048576 | round)MB\t\(.worktree)" +
    (if .rescuedTo then "\n  rescued: untracked files copied to \(.rescuedTo)" else "" end) +
    (if (.blockers|length) > 0 then "\n" + ([.blockers[] | "  refused: \(.kind) - \(.detail)"] | join("\n")) else "" end))
'
[ "$EXECUTE" = true ] || [ "$MODE" = quick ] \
  || printf '\nnothing was removed: this was a dry run. Re-run with --execute to reclaim.\n'

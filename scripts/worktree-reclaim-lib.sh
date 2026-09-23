#!/usr/bin/env bash
# Read-only verdict on whether one agent worktree can be reclaimed.
#
# This library NEVER writes, moves or deletes anything. It answers one question about one directory
# - "would removing this destroy work?" - as a `harness-worktree-reclaim.v1` JSON object, and every
# reason it says no is named in `blockers` with the path or count a person can act on. The acting
# half lives in scripts/worktree-sweep.sh, so the decision can be read, tested and reused without
# any caller risking a removal it did not ask for.
#
# Source after scripts/herdr-runtime-lib.sh.

# A worktree is a candidate only when it is unambiguously a LINKED git worktree rooted exactly at
# the path we were handed. Three separate traps this closes, each of which turns a cleanup tool into
# a data-loss tool:
#   1. `git -C <dir>` walks UP. A leftover directory whose git metadata is gone, sitting inside a
#      clone, answers every question about its PARENT repo - so a naive check reports the parent's
#      clean state and the removal takes a directory git never knew about.
#   2. A main checkout has git-dir == git-common-dir; a linked worktree does not. Requiring them to
#      differ means the sweep can never target a project clone or the harness root itself.
#   3. --show-toplevel must equal the path itself, so a subdirectory of a worktree is not mistaken
#      for the worktree.
# Anything that fails these is REFUSED, never removed: an orphan whose registration vanished is
# exactly the case where git can no longer tell us what would be lost.
worktree_reclaim_shape() {
  local path=$1 top gitdir commondir
  [ -e "$path/.git" ] || { printf 'not-a-worktree\n'; return; }
  top=$(git -C "$path" rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || {
    printf 'git-unreadable\n'; return; }
  gitdir=$(git -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null) || {
    printf 'git-unreadable\n'; return; }
  commondir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    printf 'git-unreadable\n'; return; }
  [ "$(cd "$top" 2>/dev/null && pwd -P)" = "$(cd "$path" && pwd -P)" ] || { printf 'not-a-worktree\n'; return; }
  [ "$gitdir" != "$commondir" ] || { printf 'main-checkout\n'; return; }
  printf 'linked\n'
}

# The repository that owns a linked worktree: the parent of its git-common-dir.
worktree_reclaim_repo() {
  local path=$1 commondir
  commondir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  (cd "$commondir/.." 2>/dev/null && pwd -P) || return 1
}

# One system-wide `lsof` snapshot of every process's current working directory, cached for the run.
# This is how a live agent is recognised in a worktree the harness never recorded - the
# `.claude/worktrees/` and `~/.treehouse/` copies a tool other than agent-spawn.sh created, which no
# task metadata will ever mention. `lsof -d cwd` reads one descriptor per process rather than
# descending the tree, so it costs the same whether the worktree holds ten files or a node_modules.
WORKTREE_RECLAIM_CWDS=''
worktree_reclaim_live_cwds() {
  if [ -z "$WORKTREE_RECLAIM_CWDS" ]; then
    if command -v lsof >/dev/null 2>&1; then
      WORKTREE_RECLAIM_CWDS=$(lsof -d cwd -F n 2>/dev/null | sed -n 's/^n//p' | sort -u)
    fi
    # A single space marks "already attempted" so an empty result is not recomputed every call.
    WORKTREE_RECLAIM_CWDS=${WORKTREE_RECLAIM_CWDS:- }
  fi
  printf '%s\n' "$WORKTREE_RECLAIM_CWDS"
}

worktree_reclaim_process_live() {
  local path=$1
  command -v lsof >/dev/null 2>&1 || return 1
  worktree_reclaim_live_cwds | grep -qxF "$path" && return 0
  worktree_reclaim_live_cwds | grep -q "^$(printf '%s' "$path" | sed 's/[][\.^$*/]/\\&/g')/" && return 0
  return 1
}

# A harness-spawned worktree is recorded by path in a task's runtime metadata. That record is the
# authoritative live check for everything agent-spawn.sh created: metadata that is not `stopped=1`
# and whose Herdr agent still answers means an agent owns this directory right now.
# `agent_status` returning `unknown` means Herdr has no such agent - the died-without-reporting case
# a sweep exists to catch - so that is deliberately NOT treated as live.
# Built once per run, in one awk pass over every task metadata file, as `<worktree>\t<meta>` lines.
# Doing it per candidate instead cost two `sed` invocations per metadata file per worktree - with
# 336 recorded tasks and 45 candidates that is 30,000 processes, and it dominated the whole sweep.
WORKTREE_RECLAIM_INDEX=''
worktree_reclaim_index() {
  if [ -z "$WORKTREE_RECLAIM_INDEX" ]; then
    WORKTREE_RECLAIM_INDEX=$(mktemp)
    awk -F= '
      function emit() { if (schema == "harness-herdr-task.v1" && worktree != "") print worktree "\t" file }
      FNR == 1 { if (file != "") emit(); file = FILENAME; schema = ""; worktree = "" }
      $1 == "schema" { schema = $2 }
      $1 == "worktree" { worktree = substr($0, index($0, "=") + 1) }
      END { if (file != "") emit() }
    ' "$HARNESS_STATE"/*.meta > "$WORKTREE_RECLAIM_INDEX" 2>/dev/null || true
  fi
  printf '%s\n' "$WORKTREE_RECLAIM_INDEX"
}

worktree_reclaim_recorded_task() {
  local path=$1 line recorded
  while IFS= read -r line; do
    recorded=${line%%$'\t'*}
    [ "$recorded" = "$path" ] || [ "$(cd "$recorded" 2>/dev/null && pwd -P)" = "$path" ] || continue
    printf '%s\n' "${line#*$'\t'}"
    return 0
  done < "$(worktree_reclaim_index)"
  return 1
}

worktree_reclaim_metadata_live() {
  local meta=$1
  [ -f "$meta" ] && [ ! -L "$meta" ] || return 1
  [ "$(meta_get "$meta" stopped)" != 1 ] || return 1
  command -v herdr >/dev/null 2>&1 || return 0
  [ "$(agent_status "$(meta_get "$meta" agent_name)" "$(meta_get "$meta" session)")" != unknown ]
}

worktree_reclaim_mtime() {
  local target=$1
  stat -f %m "$target" 2>/dev/null || stat -c %Y "$target" 2>/dev/null || printf '0'
}

# Last activity: the newest of the worktree directory itself, its git index (touched by any status,
# add or commit an agent runs) and the HEAD commit date. Deliberately not a full-tree scan - a
# worktree carries a node_modules and the age gate is a backstop, not the live check.
worktree_reclaim_last_active() {
  local path=$1 gitdir newest candidate
  newest=$(worktree_reclaim_mtime "$path")
  gitdir=$(git -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null) || gitdir=''
  if [ -n "$gitdir" ] && [ -f "$gitdir/index" ]; then
    candidate=$(worktree_reclaim_mtime "$gitdir/index")
    [ "$candidate" -le "$newest" ] || newest=$candidate
  fi
  candidate=$(git -C "$path" log -1 --format=%ct 2>/dev/null) || candidate=''
  if [ -n "$candidate" ] && [ "$candidate" -gt "$newest" ]; then newest=$candidate; fi
  printf '%s\n' "$newest"
}

# SAFETY CASE 2 - commits that exist only here.
#
# Reachability first, then CONTENT, because reachability alone is wrong in both directions. A branch
# whose commits were squashed or rebased into the base is fully upstream while no remote ref reaches
# a single one of its shas; a commit that reverts to the base tree carries nothing to lose. So:
#   a) nothing reachable from HEAD is outside every remote-tracking ref  -> clear;
#   b) the branch introduces no diff against its base at all (a stub, or content already merged)
#      -> clear;
#   c) `git cherry` finds an equivalent patch upstream for every local commit -> clear;
# and only what survives all three is reported, by sha, as work that would be destroyed.
worktree_reclaim_unpushed() {
  local path=$1 base cand
  git -C "$path" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || return 0
  [ -n "$(git -C "$path" rev-list -1 HEAD --not --remotes 2>/dev/null)" ] || return 0
  base=$(git -C "$path" rev-parse --verify --quiet '@{upstream}' 2>/dev/null) || base=''
  if [ -z "$base" ]; then
    for cand in refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master; do
      base=$(git -C "$path" rev-parse --verify --quiet "$cand" 2>/dev/null) && break
      base=''
    done
  fi
  if [ -z "$base" ]; then
    git -C "$path" rev-list HEAD --not --remotes 2>/dev/null
    return 0
  fi
  git -C "$path" diff --quiet "$base...HEAD" 2>/dev/null && return 0
  git -C "$path" cherry "$base" HEAD 2>/dev/null | awk '$1 == "+" { print $2 }'
}

# SAFETY CASE 3 - content git has never heard of.
#
# `--exclude-standard` is the whole point: a gitignored node_modules or .next is regenerable and must
# not block anything, while a directory of screenshots and a run description that nobody ever added
# is irreplaceable and blocks unconditionally. `ls-files --others` enumerates FILES inside untracked
# directories, unlike `status --porcelain`, which collapses them to one line and would have reported
# a 17 MB tree as a single unremarkable entry.
worktree_reclaim_untracked() {
  git -C "$1" ls-files --others --exclude-standard 2>/dev/null
}

# SAFETY CASE 1 - modified tracked files, staged or not.
worktree_reclaim_uncommitted() {
  git -C "$1" status --porcelain --untracked-files=no 2>/dev/null
}

# `du` walks every inode under the worktree, and a worktree carrying a node_modules costs 1-2
# seconds of that on its own (measured 2026-09-23: 1.5 GB in 1.3 s, 2.0 GB in 2.0 s). Worth paying
# when a person asked how much there is to reclaim; not worth it for a session-start one-liner, which
# sets WORKTREE_RECLAIM_SIZES=false.
#
# This is a `du` figure and it is an UPPER BOUND on what removal frees, not a prediction. On APFS,
# pnpm's default import method clones rather than hardlinks, and `du` cannot see block sharing:
# measured 2026-09-23, two 50 MB clones read as 100 MB to `du` while `df` free space moved by 12 KB.
# Reported as GB (du) for that reason - never quote it as reclaimed space without a df measurement.
worktree_reclaim_bytes() {
  local path=$1 out
  [ "${WORKTREE_RECLAIM_SIZES:-true}" = true ] || { printf '0\n'; return; }
  out=$(du -sk "$path" 2>/dev/null | awk 'NR==1{print $1}') || out=''
  [ -n "$out" ] || { printf '0\n'; return; }
  printf '%s\n' "$((out * 1024))"
}

# Build both per-run caches in the CALLING shell. A caller that inspects many worktrees runs each
# inspection in a command substitution, and a subshell inherits variables but cannot write them back
# - so without this the lsof snapshot and the metadata index are rebuilt once per candidate. Priming
# them first took a 45-worktree quick sweep from 50 s to 12 s (measured 2026-09-23). The caller owns
# the index file: worktree_reclaim_release removes it.
worktree_reclaim_prime() {
  worktree_reclaim_live_cwds >/dev/null
  worktree_reclaim_index >/dev/null
}

worktree_reclaim_release() {
  [ -z "$WORKTREE_RECLAIM_INDEX" ] || rm -f "$WORKTREE_RECLAIM_INDEX"
  WORKTREE_RECLAIM_INDEX=''
}

# Emit one harness-worktree-reclaim.v1 observation for $1.
# $2 is the age threshold in days; anything touched more recently is refused as possibly live.
# $3 is `full` (default) or `quick`. Quick answers only "is this a candidate, how old, is anyone in
# it" - the questions that cost milliseconds - and skips the git content checks, which on a real
# project tree cost around two seconds each (measured 2026-09-23: 45 worktrees, 93 s). A quick
# observation is NEVER reclaimable; it carries a `not-inspected` blocker so a caller cannot mistake
# "we did not look" for "there is nothing here".
worktree_reclaim_inspect() {
  local path=$1 threshold=${2:-7} mode=${3:-full} shape repo branch task meta blockers now last age
  local uncommitted untracked unpushed count sample bytes
  if ! path=$(cd "$path" 2>/dev/null && pwd -P); then
    jq -nc --arg worktree "$1" '{schema:"harness-worktree-reclaim.v1",worktree:$worktree,repo:"",branch:"",task:"",shape:"missing",ageDays:0,sizeBytes:0,blockers:[{kind:"unreadable",detail:"path no longer exists"}],reclaimable:false}'
    return
  fi
  blockers=$(mktemp)
  _wr_block() { jq -nc --arg kind "$1" --arg detail "$2" '{kind:$kind,detail:$detail}' >> "$blockers"; }

  shape=$(worktree_reclaim_shape "$path")
  repo=''; branch=''; task=''
  case "$shape" in
    linked) repo=$(worktree_reclaim_repo "$path") || repo='' ;;
    main-checkout) _wr_block main-checkout "$path is a repository's main checkout, not an agent worktree" ;;
    not-a-worktree) _wr_block not-a-worktree "$path is not the root of a linked git worktree" ;;
    git-unreadable) _wr_block git-unreadable "$path has git metadata that cannot be read; remove it by hand after checking what is in it" ;;
  esac

  now=$(date +%s)
  last=$(worktree_reclaim_last_active "$path")
  age=$(( (now - last) / 86400 ))
  [ "$age" -ge 0 ] || age=0

  # --- live-agent checks: these run whatever the shape, because "someone is working here" outranks
  #     every other consideration and must be reported even for a directory we would refuse anyway.
  if meta=$(worktree_reclaim_recorded_task "$path"); then
    task=$(meta_get "$meta" task)
    if worktree_reclaim_metadata_live "$meta"; then
      _wr_block live-agent "task $task is running here (runtime metadata $meta is not stopped and its Herdr agent answers)"
    fi
  fi
  if worktree_reclaim_process_live "$path"; then
    _wr_block live-process "a running process has its working directory inside $path"
  fi
  if [ "$age" -lt "$threshold" ]; then
    _wr_block recently-active "last activity $age day(s) ago, under the $threshold-day threshold"
  fi

  if [ "$shape" = linked ] && [ "$mode" = quick ]; then
    _wr_block not-inspected "not inspected for uncommitted, unpushed or untracked work; run worktree-sweep.sh without --quick for a verdict"
  elif [ "$shape" = linked ]; then
    branch=$(git -C "$path" branch --show-current 2>/dev/null) || branch=''

    uncommitted=$(worktree_reclaim_uncommitted "$path")
    if [ -n "$uncommitted" ]; then
      count=$(printf '%s\n' "$uncommitted" | wc -l | tr -d ' ')
      sample=$(printf '%s\n' "$uncommitted" | head -5 | sed 's/^...//' | paste -sd, -)
      _wr_block uncommitted-changes "$count modified tracked file(s): $sample"
    fi

    unpushed=$(worktree_reclaim_unpushed "$path")
    if [ -n "$unpushed" ]; then
      count=$(printf '%s\n' "$unpushed" | wc -l | tr -d ' ')
      sample=$(printf '%s\n' "$unpushed" | cut -c1-8 | head -5 | paste -sd, -)
      _wr_block unpushed-commits "$count commit(s) on $branch neither reachable from a remote ref nor present upstream by content: $sample (fetch the remote first if these refs are stale)"
    fi

    untracked=$(worktree_reclaim_untracked "$path")
    if [ -n "$untracked" ]; then
      count=$(printf '%s\n' "$untracked" | wc -l | tr -d ' ')
      sample=$(printf '%s\n' "$untracked" | head -5 | paste -sd, -)
      _wr_block untracked-files "$count untracked, non-ignored file(s) git has no copy of: $sample"
    fi
  fi

  bytes=$(worktree_reclaim_bytes "$path")
  jq -nc --arg schema harness-worktree-reclaim.v1 --arg worktree "$path" --arg repo "$repo" \
    --arg branch "$branch" --arg task "$task" --arg shape "$shape" \
    --argjson ageDays "$age" --argjson sizeBytes "$bytes" \
    --slurpfile blockers "$blockers" \
    '{schema:$schema,worktree:$worktree,repo:$repo,branch:$branch,task:$task,shape:$shape,ageDays:$ageDays,sizeBytes:$sizeBytes,blockers:$blockers,reclaimable:($blockers|length==0)}'
  rm -f "$blockers"
}

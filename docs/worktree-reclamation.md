# Worktree reclamation

Every agent gets its own git worktree with its own installed dependencies, and until 2026-09-23
nothing removed one unless a lead drove `scripts/task-teardown.sh` through its full ceremony.
Measured that morning: 36 abandoned worktrees, 17 of them dated 1-4 September and still present
three weeks later, 7 created the previous day, on a machine at 94% full.

`scripts/worktree-reclaim-lib.sh` answers "would removing this destroy work?" and writes nothing.
`scripts/worktree-sweep.sh` finds candidates and acts on the answer. The split is deliberate: the
decision can be read, tested and reused without any caller risking a removal it did not ask for.

## Where cleanup belongs, and why not somewhere else

`task-teardown.sh` is not replaced. It remains the ordinary route for a task that finishes properly:
card `done`, agent stopped, Clean Slate evidence archived, branch published, then the worktree goes
and the branch stays. The problem is that every leaked worktree is one that never arrived there.

- **On agent completion** is too early. `agent-review.sh` reuses one worktree for every reviewer and
  fix round of a task id, and the lead reads a run's evidence out of the worktree after the agent is
  gone. Reclaiming at completion breaks both.
- **On card close** and **on PR merge** fire only where `task-teardown.sh` already fires. Not one of
  the 36 reached a close or a merge, so a hook there would have collected none of them.
- **A sweep** is the only thing that sees a worktree whose owner died without reporting, and the only
  thing that sees one the harness never created. The largest group of the 36 sat under
  `<repo>/.claude/worktrees/` and `~/.treehouse/`, written by Claude Code's `EnterWorktree` and by
  treehouse. No harness hook fires for those, whichever hook is chosen.

A sweep's own risk is the mirror image, taking something still wanted. The live checks and the age
threshold are the answer to that, not the choice of trigger.

## What blocks a removal

Each of these refuses, names the path and the count, and is proved by `tests/worktree-sweep.test.sh`.
Silence is how 45 GB accumulated, so a refusal is never a shrug.

| blocker | how it is decided |
| --- | --- |
| `live-agent` | the worktree is recorded in a task's runtime metadata that is not `stopped=1`, and its Herdr agent still answers |
| `live-process` | a running process has its working directory inside the worktree, from one system-wide `lsof -d cwd` snapshot |
| `recently-active` | newest of the directory mtime, the git index mtime and the HEAD commit date is inside the threshold (default 7 days) |
| `uncommitted-changes` | `git status --porcelain --untracked-files=no` is non-empty |
| `unpushed-commits` | see below |
| `untracked-files` | `git ls-files --others --exclude-standard` is non-empty |
| `main-checkout`, `not-a-worktree`, `git-unreadable` | the directory is not unambiguously a linked worktree rooted exactly there |

**Unpushed commits are decided by content, not only by reachability.** Reachability alone is wrong in
both directions: a branch squashed or rebased into the base is fully upstream while no remote ref
reaches one of its shas, and a commit that reverts to the base tree carries nothing to lose. Of the
three worktrees found holding local commits, two were already upstream by content and one was a stub.
So the check is: nothing outside every remote-tracking ref clears immediately; otherwise an empty
three-dot diff against the base clears; otherwise `git cherry` must find an equivalent patch upstream
for every commit. Only what survives all three is reported, by sha. Stale remote-tracking refs make
this refuse rather than proceed, and the message says to fetch.

**Untracked files are the case implementations get wrong.** `--exclude-standard` is the whole point:
a gitignored `node_modules` or `.next` is regenerable and must not block anything, while a directory
of screenshots nobody ever added is irreplaceable and blocks unconditionally. One of the 36 held a
17 MB `demo/` directory and a run description from 28 August that no git object knew about. Note also
that `ls-files --others` enumerates files inside untracked directories; `status --porcelain` collapses
them to one line and would have reported that tree as a single unremarkable entry.

`--rescue <dir>` is the opt-in alternative to refusing: untracked files are copied out with their
relative paths, verified, removed from the worktree, and the destination is printed. It applies only
to untracked content. Modified tracked files and unpushed commits live in git's own object model and
a copy is not an equivalent record of them, so those always refuse.

## Live versus dead

Two independent signals, because neither covers the whole population.

Runtime metadata is authoritative for everything `agent-spawn.sh` created: `stopped=1` means finished,
and a Herdr agent that no longer answers means the agent died without reporting - deliberately *not*
treated as live, since that is the case the sweep exists to catch.

For a worktree the harness never recorded, there is no metadata to read, so a single system-wide
`lsof -d cwd` snapshot decides it: any process whose working directory is inside the worktree holds
it. That costs one `lsof` per run rather than a walk per worktree.

The age threshold is the backstop under both. It uses the newest of the directory mtime, the git index
mtime and the HEAD commit date, which is cheap and errs towards "recent". It is not the live check, it
is what catches a worktree neither signal can speak for.

## Running it

```bash
scripts/worktree-sweep.sh                       # dry run over every known root, a verdict each
scripts/worktree-sweep.sh --quick               # census only, seconds instead of a minute
scripts/worktree-sweep.sh --root <path>         # only there; --root replaces the defaults
scripts/worktree-sweep.sh --older-than 14       # a different threshold
scripts/worktree-sweep.sh --rescue ~/rescued --execute
scripts/worktree-sweep.sh --execute             # reclaim what passed every gate
```

Nothing is removed without `--execute`. No branch is ever deleted. `--execute` from inside a linked
Jarvis task worktree is refused, like every other fleet mutation. `scripts/session-start.sh` runs the
quick census so the number is never invisible again.

## On the size figures

Every byte total the sweep prints is labelled `GB (du)` because that is what it is, and on APFS it
overstates real disk by roughly five times. pnpm's default `package-import-method=auto` clones from
the store rather than hardlinking, and a clone has a link count of 1 while sharing blocks, which `du`
cannot see. Measured 2026-09-23: two 50 MB clones read as 100 MB to `du` while `df` free space moved
12 KB; `pnpm add express` into two empty directories reported 3.7 MB each to `du` while costing 332 KB
and 636 KB of real disk. Removing the 36 worktrees, about 45 GB by `du`, moved free space by about
9 GB.

The practical consequence is that a shared pnpm store is not worth pursuing here - it is already in
effect, just invisibly - and that a `du` figure must never be quoted as space reclaimed.

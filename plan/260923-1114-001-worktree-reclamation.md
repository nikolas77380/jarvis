# 260923-1114-001 - worktree reclamation

**Status:** in-review · **Owner:** lead · **Blocks:** - · **Depends on:** -
**Validation:** strict
**Engine:** claude
PR: #8
**Next:** review the PR against `origin/main`, then decide whether the sweep should run on a
schedule or stay a command the lead invokes; the shared pnpm store question below is answered and
needs no card.
**Owns:** scripts/worktree-reclaim-lib.sh, scripts/worktree-sweep.sh, tests/worktree-sweep.test.sh,
docs/worktree-reclamation.md, scripts/session-start.sh, AGENTS.md, RULES.md

## What and why

Nothing in the harness removed an agent worktree unless a lead drove `task-teardown.sh` through its
full ceremony, and almost nothing reached it. Measured on this machine 2026-09-23: 36 abandoned
worktrees, about 45 GB by `du`; 17 dated 1-4 September and still present three weeks later; 7 from
the previous day. The disk was at 94% with 28 GB free. They were cleared by hand, which fixes one
morning and nothing else.

Three of those worktrees would have been damaged by a naive `rm -rf`, and the third case decides the
design:

1. Several held modified tracked files.
2. Three held commits no remote ref reached. Two were already upstream by content and one was a
   stub, which is exactly why the check has to be content-or-reachability rather than an assumption
   in either direction.
3. One held a 17 MB `demo/` directory of screenshots and a run description from 28 August that no
   git object knew about. A cleanup respecting only git state deletes that silently.

So the deliverable is a gate first and a reclaimer second, plus the written obligation, because a
mechanism without the rule gets bypassed by the next agent that makes a worktree by hand.

## Scope

- `scripts/worktree-reclaim-lib.sh` - the read-only verdict. Never writes, moves or deletes.
- `scripts/worktree-sweep.sh` - discovery and the acting half. Dry run unless `--execute`.
- `tests/worktree-sweep.test.sh` - all three dangerous states, live vs dead agent, the age backstop,
  main-checkout refusal, rescue, and a successful reclaim, against throwaway worktrees it builds.
- `scripts/session-start.sh` - a census line, so the count is never invisible again.
- `AGENTS.md` and `RULES.md` - the obligation, in each file's own voice.
- `docs/worktree-reclamation.md` - the argument, and the alternatives rejected.

**Out of scope:** `task-teardown.sh`, which stays the ordinary route for a task that finishes
properly and is not replaced; branch deletion, which nothing here ever does.

### Why a sweep, and not a lifecycle hook

Weighed against the alternatives, with the failure mode of each:

- **On agent completion** is too early. `agent-review.sh` deliberately reuses one worktree for every
  reviewer and fix round of a task id, and the lead reads a run's evidence out of the worktree after
  the agent is gone. Reclaiming at completion breaks both.
- **On card close** and **on PR merge** cover only the path `task-teardown.sh` already covers, and
  not one of the 36 leaked worktrees reached a close or a merge. A hook on the happy path cannot
  collect the unhappy ones, and the unhappy ones are the entire population.
- **A sweep** is the only thing that can see a worktree whose owner died without reporting, and the
  only thing that can see one the harness never created. The largest group of the 36 sat under
  `<repo>/.claude/worktrees/` and `~/.treehouse/`, written by `EnterWorktree` and by treehouse. No
  harness hook fires for those, whichever hook is chosen.

The sweep's own risk is the mirror image, reclaiming something still wanted, and that is what the
live checks and the age threshold answer - not the choice of trigger.

## Done means

- `bash tests/worktree-sweep.test.sh` passes.
- `shellcheck -x scripts/worktree-sweep.sh scripts/worktree-reclaim-lib.sh scripts/session-start.sh`
  is clean.
- `scripts/worktree-sweep.sh` run against the real roots names a refusal reason and a path for every
  worktree it will not touch, and protects the worktree of the agent running at the time.

## Decisions settled here

**A shared pnpm store is not worth pursuing: it is already in effect, and the 45 GB was never 45 GB
of disk.** The obvious read of the measurement is that most of a worktree is `node_modules` and a
hardlinked store would make reclamation less urgent. Measured 2026-09-23, that is wrong on this
machine:

- pnpm 10.34.5, store at `~/Library/pnpm/store/v10`, 1.5 GB, on the same APFS volume as every
  worktree.
- The same file in the bridgeks-app main checkout and two of its `.claude/worktrees/` copies has
  three different inodes and a link count of 1 on each. Nothing is hardlinked, which is what makes
  the shared-store idea look unimplemented.
- But link count 1 does not mean a second copy on disk. pnpm's default `package-import-method=auto`
  prefers APFS `clonefile` over hardlinking, and a clone has link count 1 while sharing blocks.
  `du` cannot see that: two 50 MB clones read as 100 MB to `du` while `df` free space moved 12 KB.
- The controlled version: `pnpm add express` into two empty directories. `du` reports 3.7 MB each;
  `df` free space fell 332 KB for the first install and 636 KB for the second. Real cost is roughly
  a tenth to a sixth of the `du` figure.
- Corroborating, though not a clean measurement: removing the 36 worktrees (about 45 GB by `du`)
  moved free space from about 28 GB to about 37 GB. Around a fifth, in the same range.

So the per-worktree cost is not 1.5-2.0 GB of disk, it is a fraction of that, and a shared store has
almost nothing left to win. The sweep is still worth having - a fifth of 45 GB is still 9 GB, and
the count grows without bound - but nobody should spend a card on `package-import-method=hardlink`.
The one lasting consequence is reporting discipline: the sweep labels its totals `GB (du)`, because
quoting a `du` figure as reclaimed space would be wrong by a factor of five.

## Decisions still open

- Whether the sweep should run on a schedule rather than by hand. It is deliberately a command for
  now: a scheduled destructive job wants more operating history behind the gate than one day of it.

## Rounds

Awaiting review round 1.

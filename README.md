# Agent harness — central Herdr control home

One planning lead orchestrates visible Claude or Codex agents across multiple repositories. The harness stays
in one control home; project clones live under `projects/`, task worktrees are isolated, and every
agent runs in its own persistent Herdr tab. Plans and runtime state survive the lead conversation.

Extracted from `bridgeks` on 2026-08-20, after two days of measured use, and moved out of that repo
the same day: it lives at `~/projects/harness` so it survives any git operation in a project and can
be pulled into the next one. **Synced against `bridgeks` on 2026-08-26**, picking up six days of rule
changes: shell discipline, script-minted task ids and the plan-integrity gate, measurement provenance,
the lead's context/spend protocol, and the `design-qa` visual tier. **Read `docs/evidence.md`** — every
rule here came from a number or an incident, and a rule whose reason is known survives an argument.

## What's in here

```
RULES.md                       central orchestration rules supplied to every agent
agents/orchestrator.md         the lead — plans, delegates, verifies, never writes app code
agents/engineer.md             implementer template (one per stack), sonnet
agents/reviewer.md             logic-tier reviewer template (one per stack), opus
agents/mechanical-reviewer.md  cheap reviewer for diffs that decide nothing, sonnet
agents/deputy.md               the lead's hands: searches, specified edits, script runs — 15 lines back
agents/design-qa.md            visual tier: PR vs its design reference, own worktree, read-only
templates/plan-INDEX.md        the plan index — one line per task
templates/plan-task-card.md    one card per task; fixes the header line every script reads
templates/OVERVIEW.md          the running log, with the insert marker the script needs
templates/reports-README.md    the report convention
templates/husky-pre-commit     pre-commit hook that runs the plan-integrity check locally
templates/ci-plan-integrity.yml  the same check as its OWN CI job, so no earlier red step masks it
templates/dashboard/           zero-dependency plan dashboard that new-task.sh regenerates
scripts/checkpoint.sh          run when an agent reports back: fails while the card is stale
scripts/handoff.sh             end a session cleanly and print the next session's opening prompt
scripts/review-rounds.sh       review rounds that actually RAN, vs what the card claims
scripts/overview-append.sh     append to OVERVIEW.md without reading it first
scripts/agent-spend.sh         diagnostic pipeline spend by role
scripts/context-size.sh        context split into delegation vs own work, per agent; statusLine source
scripts/onboard-project.sh     install plan/TEMPLATE.md, plan/INDEX.md, OVERVIEW.md, reports/README.md into a project — and COMMIT, once
scripts/new-task.sh            mint a task id, card, INDEX row and dashboard — and COMMIT, in one step
scripts/plan-check.sh          every card must be tracked by git and linked from plan/INDEX.md
scripts/owns-check.sh          refuses two ACTIVE cards claiming the same file or glob
memory/                        portable pipeline lessons for an agent's memory store, with its own README
scripts/agent-*.sh             spawn, list, inspect, wait on, steer, focus and stop Herdr agents
scripts/task-teardown.sh       archive a completed task and safely remove only its worktree
scripts/session-start.sh       read-only plan/runtime recovery view
scripts/clean-slate-protocol.sh bounded review, project checks, PR and CI gate
scripts/fleet-snapshot.sh      structured local state for every recorded or planned task
scripts/harness-doctor.sh      read-only drift diagnosis
scripts/agent-reconcile.sh     conservative explicit runtime metadata repair
scripts/events-poll.sh         append actionable fleet transitions to the durable inbox
scripts/inbox.sh               list, acknowledge and drain durable events
scripts/decisions.sh           open, list and resolve keyed captain decisions
scripts/memory-context.sh      load captain, harness and one project's durable memory
scripts/memory-record.sh       record a scoped incident without promoting it
scripts/memory-promote.sh      explicitly promote an incident with provenance
projects/                      local project clones, gitignored
.harness-state/                local Herdr task identities, gitignored
docs/evidence.md               the measurements behind every rule, and what is NOT yet proven
```

## Initial setup

1. On a fresh macOS clone of this repository, run `./bootstrap.sh`. It requires
   [Homebrew](https://brew.sh) to already be installed (it never installs Homebrew itself — if
   missing, it prints the official command and stops); installs `git` and `jq` with Homebrew only if
   missing, never upgrading an existing install; installs `herdr` with the official
   `curl -fsSL https://herdr.dev/install.sh | sh` if missing; installs Claude Code with the official
   stable native installer `curl -fsSL https://claude.ai/install.sh | bash -s stable` if missing;
   links `~/.local/bin/jarvis` to this clone's `bin/jarvis` and adds `~/.local/bin` to `PATH` via
   `${ZDOTDIR:-~}/.zprofile`; and finishes by verifying the setup and printing the next two commands
   (`claude` to authenticate, `jarvis claude` to start). It never authenticates or starts Jarvis
   itself, and it is safe to re-run. Non-macOS platforms are not supported.
2. Clone each managed project under its stable central name:

   ```bash
   git clone <origin> projects/bridgeks
   git clone <origin> projects/marketplace
   ```

   Each clone owns its project-specific `CLAUDE.md` or `AGENTS.md`. Do not copy the central harness
   scripts or memory into it.
3. Onboard each project into the plan pipeline — **inside its own clone**, never at the harness
   root: `scripts/herdr-runtime-lib.sh` resolves a task card by scanning every `projects/*/plan/`
   plus the harness root's own `plan/`, and that root `plan/` is reserved for project id `jarvis`
   (the harness dogfooding itself through the same pipeline) — never for an ordinary nested project.
   Each project's own worktrees only ever contain what its own repo commits:

   ```bash
   scripts/onboard-project.sh bridgeks
   ```

   This installs `plan/TEMPLATE.md`, `plan/INDEX.md`, `OVERVIEW.md` and `reports/README.md` from
   `templates/` into `projects/bridgeks/` and commits them in one step. The lead does this itself,
   automatically, the first time it is asked to work on a project with no `plan/` yet — see
   `agents/orchestrator.md`.
4. Instantiate central roles in `agents/`. For example, copy `engineer.md` to `web-engineer.md` and
   fill its placeholders. The task card's `Owner` must equal the role filename without `.md`.
5. Mint cards with `scripts/new-task.sh <slug>` run from inside the project's own clone, fill `Owner`,
   brief and checks, then run `scripts/agent-spawn.sh <task-id>` from the harness root.

### Placeholders

| placeholder | meaning | example |
|---|---|---|
| `{{PROJECT}}` | repo name and one-line description | `bridgeks — investor platform monorepo` |
| `{{STACK}}` | short stack name, used in agent names | `web`, `api`, `rn` |
| `{{APP_PATH}}` | the path that agent owns | `apps/investor-web` |
| `{{BASE_BRANCH}}` | branch PRs target | `master` |
| `{{TEST_CMD}}` `{{TYPECHECK_CMD}}` `{{LINT_CMD}}` `{{BUILD_CMD}}` | the checks, verbatim | `pnpm --filter web test` |
| `{{CONTRACTS_PKG}}` | shared schema package | `@scope/contracts` |
| `{{DESIGN_SYSTEM}}` | design-system package | `@scope/ui-kit` |
| `{{LANG}}` | the one language everything committed is written in | `English` |
| `{{AGENT}}` | owner named on a task card | `web-engineer` |

## The shape, in one paragraph

The lead plans with you, writes a task card, and dispatches — it never writes application code, and it
does no file work at all: searches, specified multi-file edits, script runs and debugging go to
`deputy`, whose tool traffic dies with it. Cheap implementers work in isolated worktrees and take a
task to an open PR; they are told to **stop and ask** rather than guess when they meet a decision that
isn't theirs, which is what makes a cheap tier safe. Review splits by what a diff *decides*, not by its
size: the logic tier gets anything touching auth, money, domain semantics, queries or schemas — and
everything ambiguous — while the mechanical tier gets renames and formatting and answers `ESCALATE`
when a diff turns out not to be mechanical; a UI PR then gets `design-qa` after the code review
approves and before merge, measuring the running page against its design reference in its own
worktree. Nothing merges without you. State lives in `plan/` (what we intend), `OVERVIEW.md` (what
happened) and `reports/` (what one run did), so a session can end without losing anything — which
matters because a long planning session is the most expensive thing in the pipeline.

The lead's session is therefore deliberately short, and the boundary is a **card state transition**
(plan → brief written; brief → PR open; PR → review round closed; approved → merged), one per session.
The card is written the moment an agent reports back, not at the end of the day — `checkpoint.sh`
refuses to pass while it is stale — because interrupted sessions and dead agent runs happen mid-task,
and whatever is not on the card then is lost. Context size is diagnostic and never forces a reset.
Each card carries a `**Next:**` line holding the literal next dispatch, so a fresh session executes
an instruction instead of reconstructing a plan. See `docs/evidence.md` for the arithmetic that
makes this worth the discipline.

## Herdr runtime

Agents run as visible, persistent Herdr tabs rather than ephemeral native subagents. Herdr is the
only runtime; there is no tmux adapter or generic backend layer.

The normal entry point is the persistent interactive Jarvis orchestrator. `./bootstrap.sh` (see
[Initial setup](#initial-setup)) already links `jarvis` onto `PATH` via `~/.local/bin`; `install-alias`
below is the older, manual alternative for a checkout that was not bootstrapped:

```bash
bin/jarvis install-alias   # alternative to bootstrap.sh's symlink; once, then reload zsh
jarvis                     # start with the configured default, or attach if already running
jarvis claude              # explicitly start on Claude
jarvis codex               # explicitly start on Codex
jarvis switch codex        # move Jarvis to a fresh Codex conversation
jarvis status
jarvis stop
```

Talk directly to Jarvis in Herdr. Jarvis creates task cards and uses the lower-level commands below
to delegate and observe project work; they are not the normal user interface.

```bash
scripts/session-start.sh
scripts/agent-spawn.sh 260828-1200-001-example
scripts/agent-spawn.sh 260828-1200-001-example --engine codex
scripts/agent-switch.sh 260828-1200-001-example codex --note "Continue from the current Git state"
scripts/agent-list.sh
scripts/agent-state.sh 260828-1200-001-example
scripts/agent-wait.sh 260828-1200-001-example     # run in the background right after spawn/switch
scripts/quota-resume-poll.sh                       # external recovery pass, including Jarvis
scripts/quota-resume-watch.sh                      # foreground process for the external supervisor
scripts/agent-peek.sh 260828-1200-001-example 80
scripts/agent-send.sh 260828-1200-001-example "Address the review finding in src/example.ts"
scripts/agent-attach.sh 260828-1200-001-example
scripts/agent-stop.sh 260828-1200-001-example
```

Projects are central clones under `projects/<project>`. Each task card declares `Project` and `Owner`;
the runtime creates one `.harness-worktrees/<project>/<task-id>` worktree from that clone and one
Herdr tab per task. The engine is selected by explicit `--engine`, task-card `Engine`, project
configuration, global `config/harness.json`, then the Claude fallback. Both engines receive the
project instructions, central `RULES.md`, and `agents/<owner>.md`. `agent-switch.sh` can replace an
idle, done, or blocked task agent in place while preserving its branch and worktree. Exact Herdr and worktree
identities are stored locally in `.harness-state/<task-id>.meta`; both directories
are gitignored. `agent-stop.sh` closes only the recorded Herdr tab and deliberately preserves the
worktree. See [`docs/herdr-runtime.md`](docs/herdr-runtime.md) for the command and safety contract.

Context and spend scripts remain useful diagnostics, but no token threshold forces a handoff or
`/clear`. `handoff.sh` is now only an explicit transfer to another orchestrator session.

`agent-wait.sh` recognizes provider quota messages, persists `blocked_reason=quota` plus the reset
deadline under `.harness-state/quota/`, waits for that deadline, relaunches the same engine in a
fresh conversation over the preserved branch/worktree, and waits again. `events-poll.sh` also runs
`quota-resume-poll.sh`, which recovers a due task or Jarvis deadline if the original wait process did
not survive. Run `quota-resume-watch.sh` under the harness's tracked process manager so that recovery
continues while Jarvis itself is unavailable. Jarvis relaunches on its current engine with
`jarvis relaunch`.

## Clean Slate validation

`clean-slate-protocol` is the optimized, harness-native successor to Jarvis's external
`no-mistakes` command. It uses Herdr only for independent review and bounded fixes; project checks,
PR creation, and CI monitoring are deterministic. See
[`docs/clean-slate-protocol.md`](docs/clean-slate-protocol.md).

## Three things to watch when you adopt it

- **`mechanical-reviewer` has never run.** Zero runs as of 2026-08-20. The tier split is measured;
  this agent's judgement is not. Watch its first escalations, and assume it under-escalates until
  proven otherwise.
- **The checkpoint discipline is one day old.** `checkpoint.sh` and the `**Next:**` field were added
  2026-08-20 and have not survived a full task. The failure they exist for is real and observed; that
  they prevent it is not yet.
- **The bounded-review rules give a reviewer permission not to read.** That saves real money and
  removes real insurance: a fix round told to check the delta will faithfully verify the wrong thing
  if the brief names the wrong previous tip or omits a finding. The responsibility moves to the brief,
  which is why the round ceiling exists — after two rounds the lead reads the findings itself.

## Notes on the copies in here

- `scripts/*.sh` resolve paths from their own location, so they only work once copied into a project's
  `scripts/`. Running them from this folder will look for a `plan/` and an `OVERVIEW.md` next to it and
  find nothing.
- `new-task.sh` calls `scripts/dashboard-build.mjs` **in the target project**, which is why step 1
  copies the generator out of `templates/dashboard/`; without it the script degrades to card + INDEX
  row and still commits.
- `statusLine` wiring for `context-size.sh` goes in the target project's `.claude/settings.json`:
  `{ "statusLine": { "type": "command", "command": "scripts/context-size.sh --statusline" } }` — the
  relative path resolves against the session's working directory, which is the project root or a
  worktree of it.

## Keeping it in sync

This folder is a snapshot, not a symlink: when a rule changes in a project that uses it, nothing
changes here, and vice versa. Re-extract deliberately — the 2026-08-26 sync above closed a six-day
drift — or pull this repository into each project, which is worth it once a third project adopts it.

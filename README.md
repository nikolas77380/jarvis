# Agent harness — portable version

The delegation pipeline as it actually runs, with the project-specific parts pulled out. Copy this
folder into another repo, fill the placeholders, and you have the same setup: one planning lead, cheap
implementers, two review tiers, and three files that hold the state instead of a conversation.

Extracted from `bridgeks` on 2026-08-20, after two days of measured use, and moved out of that repo
the same day: it lives at `~/projects/harness` so it survives any git operation in a project and can
be pulled into the next one. **Read `docs/evidence.md`** — every rule here came from a number or an
incident, and a rule whose reason is known survives an argument.

## What's in here

```
RULES.md                    the two sections to paste into the project's CLAUDE.md
agents/orchestrator.md      the lead — plans, delegates, verifies, never writes app code
agents/engineer.md          implementer template (one per stack), sonnet
agents/reviewer.md          logic-tier reviewer template (one per stack), opus
agents/mechanical-reviewer.md  cheap reviewer for diffs that decide nothing, sonnet
templates/plan-INDEX.md     the plan index — one line per task
templates/plan-task-card.md one card per task
templates/OVERVIEW.md       the running log, with the insert marker the script needs
templates/reports-README.md the report convention
scripts/checkpoint.sh       run when an agent reports back: fails while the card is stale
scripts/handoff.sh          end a session cleanly and print the next session's opening prompt
scripts/review-rounds.sh    review rounds that actually RAN, vs what the card claims
scripts/overview-append.sh  append to OVERVIEW.md without reading it first
scripts/agent-spend.sh      what the pipeline consumed, by role, with a HANDOFF warning
scripts/context-size.sh     context split into delegation vs own work, per agent; statusLine source
docs/evidence.md            the measurements behind every rule, and what is NOT yet proven
```

## Adopting it in a new repo

1. **Copy the pieces into place.**
   ```
   H=~/projects/harness            # run the rest from the target project's root
   mkdir -p .claude/agents scripts plan reports docs/decisions docs/overview-archive
   cp -r $H/agents/. .claude/agents/          # then rename per stack, see step 2
   cp $H/scripts/*.sh scripts/ && chmod +x scripts/*.sh
   cp $H/templates/plan-INDEX.md plan/INDEX.md
   cp $H/templates/plan-task-card.md plan/TEMPLATE.md
   cp $H/templates/OVERVIEW.md OVERVIEW.md
   cp $H/templates/reports-README.md reports/README.md
   ```
   Create `docs/overview-archive/` even though it looks unused — the overview trim writes there, and
   on 2026-08-20 a trim that assumed the directory existed wrote the shortened file first and then
   failed, briefly losing three entries.
2. **Instantiate the per-stack agents.** `engineer.md` and `reviewer.md` are templates: copy one pair
   per app or stack (`web-engineer.md` + `web-reviewer.md`, `api-engineer.md` + `api-reviewer.md`) and
   fill the `name:` in the frontmatter to match the filename. `orchestrator.md` and
   `mechanical-reviewer.md` are used as-is.
3. **Paste `RULES.md`'s two sections into the project's `CLAUDE.md`** and replace the placeholders.
   Keep them in the rules file; keep the *reasoning* in `docs/decisions/` and link it — see the last
   section of `docs/evidence.md` for why that split matters.
4. **Ignore the worktrees.** Add `.claude/worktrees/` to `.gitignore` **before** committing
   `.claude/`. Agent worktrees are per-run checkouts; without this line they get staged (in our repo
   that was 30 files of duplicated tree waiting to be committed).
5. **Commit `.claude/agents/`.** The definitions belong in git — otherwise the setup exists on one
   laptop, in one worktree.
6. **Fill `plan/INDEX.md` with the real work** before dispatching anything. An empty index means the
   lead keeps the plan in its own context, which is the failure this structure removes.

### Placeholders

| placeholder | meaning | example |
|---|---|---|
| `{{PROJECT}}` | repo name and one-line description | `bridgeks — investor platform monorepo` |
| `{{STACK}}` | short stack name, used in agent names | `nextjs`, `api`, `rn` |
| `{{APP_PATH}}` | the path that agent owns | `apps/investor-web` |
| `{{BASE_BRANCH}}` | branch PRs target | `master` |
| `{{TEST_CMD}}` `{{TYPECHECK_CMD}}` `{{LINT_CMD}}` `{{BUILD_CMD}}` | the checks, verbatim | `pnpm --filter web test` |
| `{{CONTRACTS_PKG}}` | shared schema package | `@scope/contracts` |
| `{{DESIGN_SYSTEM}}` | design-system package | `@scope/ui-kit` |
| `{{AGENT}}` | owner named on a task card | `web-engineer` |

## The shape, in one paragraph

The lead plans with you, writes a task card, and dispatches — it never writes application code. Cheap
implementers work in isolated worktrees and take a task to an open PR; they are told to **stop and ask**
rather than guess when they meet a decision that isn't theirs, which is what makes a cheap tier safe.
Review splits by what a diff *decides*, not by its size: the logic tier gets anything touching auth,
money, domain semantics, queries or schemas — and everything ambiguous — while the mechanical tier
gets renames and formatting and answers `ESCALATE` when a diff turns out not to be mechanical. Nothing
merges without you. State lives in `plan/` (what we intend), `OVERVIEW.md` (what happened) and
`reports/` (what one run did), so a session can end without losing anything — which matters because a
long planning session is the most expensive thing in the pipeline.

The lead's session is therefore deliberately short, and the boundary is a **card state transition**
(plan → brief written; brief → PR open; PR → review round closed; approved → merged), one per session.
The card is written the moment an agent reports back, not at the end of the day — `checkpoint.sh`
refuses to pass while it is stale — because usage limits and dead agent runs happen mid-task, and
whatever is not on the card then is lost. Each card carries a `**Next:**` line holding the literal next
dispatch, so a fresh session executes an instruction instead of reconstructing a plan. See
`docs/evidence.md` for the arithmetic that makes this worth the discipline.

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
- `statusLine` wiring for `context-size.sh` goes in the target project's `.claude/settings.json`:
  `{ "statusLine": { "type": "command", "command": "scripts/context-size.sh --statusline" } }` — the
  relative path resolves against the session's working directory, which is the project root or a
  worktree of it.
- Nothing here is version-controlled yet. `git init` in this folder is the cheap way to stop a future
  edit from being irreversible.

## Keeping it in sync

This folder is a snapshot, not a symlink: when a rule changes in a project that uses it, nothing
changes here, and vice versa. Re-extract deliberately, or turn this into a real repository and pull it
into each project — the second is worth it once a third project adopts it.

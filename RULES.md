# The rules — paste into a project's CLAUDE.md

Two sections, meant to be copied verbatim into the project's own `CLAUDE.md` (which is what every
agent reads on every run). Replace `{{...}}` placeholders. Keep the reasoning out of this file and in
`docs/decisions/` — the rules file is read constantly, the reasoning is read once.

---

## Agent pipeline (delegation)

Sessions are normally launched as the `orchestrator` agent; whoever leads a session takes that role
regardless: plan with the user, delegate, verify, report. Never dispatch `orchestrator` as a subagent
from a session that is already leading. **Reasoning and measurements: `docs/decisions/agent-pipeline.md`.**

- **Do not write substantive application code yourself.** Anything landing in the codebase as a
  behaviour change goes to an engineer agent and then a reviewer, even when writing it inline would be
  faster. Direct edits are for the trivially mechanical (a typo, a version bump, a doc line) and for
  this file.
- **Who does what.** `Explore` — locate code and prior art, read-only. `Plan` — architecture questions
  where a decision is genuinely open. `{{STACK}}-engineer` (sonnet) — implementation in
  `{{APP_PATH}}`; it may never add or redefine a shared design-system value, it stops and asks. Runs
  with `isolation: "worktree"`, branches off `{{BASE_BRANCH}}`, goes through to an open PR.
  `{{STACK}}-reviewer` (opus) — the logic tier. `mechanical-reviewer` (sonnet) — the mechanical tier.
  `general-purpose` — shared libs, config, migrations. `deputy` (sonnet) — the lead's hands: searches, specified multi-file edits, script runs and debugging, structural verification. It decides nothing and returns 15 lines, so its tool traffic never enters the lead's context. `fork` — a sub-question already in the lead's
  context.
- **Briefing.** Fresh agents start with zero context: the actual instruction, the file paths, the
  boundary rule that applies, what is out of scope (name the files a concurrent agent owns), and
  "done" as commands. Never "implement it based on the plan".
- **Model tier follows how many decisions are left in the task after briefing, not the task's topic.**
  An implementer may be wrong about how well it did the work — never about what the work is. A brief
  that still says "find out X, then choose A or B" is a planning task in implementation clothes.
  Never hand down work whose decision is *discovered* by doing it (scout on the stronger tier first),
  or work whose success cannot be checked by running commands. Engineers are told to stop and report
  rather than guess — never write a brief that punishes using that valve.
- **Session length, checkpoints and handoff are the LEAD's protocol, and live in `agents/orchestrator.md` §2c** — not here. One line of it binds everyone: **the lead does no file work**, so if you are the lead, every search, multi-file edit, script run and debug goes to `deputy`. The rest (card state transitions as session boundaries, `scripts/checkpoint.sh` on every agent report, the `**Next:**` card field, 400k cache-read as a stop, one message per batch of independent dispatches) is read by the one session that acts on it, instead of by every agent on every turn. Reasoning and measurements: `docs/evidence.md`.
- **Review tier by what the diff decides, not by its size.** The logic tier for anything touching
  auth, money, domain semantics, data queries, shared schemas, migrations, or any conditional, error
  path or validation boundary — the default, and the answer whenever the tier is unclear.
  `mechanical-reviewer` only for diffs that rename, move, format, document, configure or test without
  changing what the code decides; it answers `ESCALATE` when that turns out false and the same PR
  crosses to the logic tier. A PR mixing both zones goes to the logic tier undivided. All reviewers
  re-run the checks themselves and never trust the engineer's summary.
- **Review is bounded — the diff is the unit, the repository is not.**
  - **One PR, one concern.** Split by concern *before* dispatching, and give the risky concern its own
    PR and its own tier. A PR that mixes three concerns is re-read in full by every round to find a
    defect that lives in one of them.
  - **A fix round reviews the DELTA**: the commit range since the previous round's tip plus the exact
    findings it must close, never the whole PR again. The **checks still run in full** — a fix can
    break what was already approved — it is the reading that is scoped.
  - **A reviewer opens a full file only when the hunk is unreadable without it**, and never sweeps the
    repo for context. Needing repo-wide knowledge to reach a verdict is evidence the PR mixes
    concerns: report that instead of reading everything.
  - **Round ceiling: two.** After the second round the lead reads the findings itself and either
    dispatches a targeted verification of one hunk or takes the decision to the user. A run that dies
    producing nothing is retried once, never with a wider scope than the run that died.
  - **The ledger is `scripts/review-rounds.sh`, and it counts what RAN, not what was written down.** It reads each card's declared `PR: #n` line, counts reviewer runs against that PR in the local transcripts, compares them with the card's `## Review round N` headings, and exits non-zero at or past the ceiling. Run it before dispatching any review. Every review brief states "round N of 2" and names the previous round's tip; a card that cannot say N gets fixed first. Written down because the rule was addressed to the lead while the lead is also told to end its session — on 2026-08-20 a card recorded one round for a PR that had had four.
- **Authority.** Engineers pushing branches and opening PRs is pre-authorized. Deploys, secret
  changes, force pushes and merging a PR are NOT: surface them to the user. Every merge to
  `{{BASE_BRANCH}}` is confirmed individually.
- **Verification before reporting.** "PR opened" is not "done": a PR-producing task needs an `APPROVE`
  verdict and the affected package's checks confirmed directly. An agent's summary describes intent,
  not outcome.
- The **why** behind past decisions lives in `plan/`, `OVERVIEW.md` and `docs/decisions/`; an agent's
  private memory store holds only what has no home in the repo.

---

## Plan, overview, reports

Three artifacts, three jobs, all in git so any agent in any folder can read them. Do NOT keep the
plan in an agent's memory store: it is invisible to every other session and goes stale within a day.

- **`plan/` — what we intend.** `plan/INDEX.md` is one line per task (id, status, owner, dependency,
  note); each task gets `plan/<Tnn>-<slug>.md` — copy `plan/TEMPLATE.md`, which fixes the header line
  (`Status` / `Owner` / `Depends on` / `PR` / **`Next`**) that `checkpoint.sh`, `handoff.sh` and
  `review-rounds.sh` all read — with goal, scope, the rationale behind decisions, and what "done"
  means. **Read `INDEX.md` first and open only the cards you need.** **Cross-task ordering
  lives in `INDEX.md`, never only inside a card**: a card read on its own cannot tell you it must wait
  for another.
- **`OVERVIEW.md` — what actually happened.** Newest first, 8–10 entries, older ones moved to
  `docs/overview-archive/YYYY-MM.md` (entry count is the rule; 60 KB is the backstop). **Append with
  `scripts/overview-append.sh "title" <<'EOF' … EOF`** — it inserts after a marker it asserts is
  unique and swaps through a temp file. Never append by reading the file and editing it: that costs
  the whole file on every entry, and a half-written overwrite destroys the only record of what
  happened.
- **`reports/<task>-<agent>.md` — the full account of one delegated run.** Specialists write the long
  version there and **return ≤15 lines**: verdict, files touched, blockers, approvals needed.
  Engineers write it in their own worktree and commit it on their branch so the path resolves for the
  reviewer; report files are out of review scope. Pass a reviewer the **path as context — the diff
  stays the evidence.**

Keeping these current is part of finishing a task: a task is not done while its card says
`in-progress`. The card is written at every checkpoint, not at the end — a session that ends without
one takes its state to the grave, and the next session pays to rediscover it.

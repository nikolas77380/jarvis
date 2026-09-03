# The rules — paste into a project's CLAUDE.md

Four sections, meant to be copied verbatim into the project's own `CLAUDE.md` (which is what every
agent reads on every run). Replace `{{...}}` placeholders. Keep the reasoning out of this file and in
`docs/decisions/` — the rules file is read constantly, the reasoning is read once. Every figure below
is a MEASUREMENT observed on `bridgeks` on the date it names, kept verbatim: a rule whose number has
been stripped is a rule nobody can defend in an argument. Never recompute or round one. Workings,
incidents and what is NOT yet proven: `docs/evidence.md`.

---

## Agent pipeline (delegation)

Sessions are normally launched as the `orchestrator` agent; whoever leads a session takes that role
regardless: plan with the user, delegate, verify, report. Never dispatch `orchestrator` as a subagent
from a session that is already leading. **Reasoning and measurements: `docs/decisions/agent-pipeline.md`.**

- **Do not write substantive application code yourself.** Anything landing in the codebase as a
  behaviour change goes to an engineer agent and then a reviewer, even when writing it inline would be
  faster. Direct edits are for the trivially mechanical (a typo, a version bump, a doc or config line)
  and for this file.
- **Who does what.** `Explore` — locate code and prior art, read-only. `Plan` — architecture questions
  where a decision is genuinely open. `engineer` (sonnet, one instance per stack) — implementation in
  `{{APP_PATH}}`; it may never add or redefine a shared design-system value or any other project-wide
  primitive (project-wide blast radius: it stops and asks). Launch it with
  `scripts/agent-spawn.sh <task-id>`; that command reads `Project` and `Owner` from the task card,
  then creates its isolated worktree
  and Herdr tab. It branches off the current approved base and goes through to an open PR. `reviewer`
  (opus, one per stack) — the logic tier.
  `mechanical-reviewer` (sonnet) — the mechanical tier. `design-qa` (sonnet) — the visual tier, own
  bullet below. `general-purpose` (opus) — shared libs, config, migrations, nothing a stack agent owns;
  like every Herdr-launched specialist it requires a matching central role file before dispatch.
  `deps-researcher` (sonnet) — read-only npm package research for JS/TS stacks: it returns a ranked,
  evidence-backed recommendation plus an install command, never installs or edits anything. **Route to
  it before adopting or replacing an npm package, and before any major version upgrade.** A patch or
  minor upgrade may proceed directly unless there is real compatibility or security uncertainty, in
  which case it routes through `deps-researcher` too. `deputy` (sonnet) — the lead's hands: searches,
  specified multi-file edits, script runs and debugging, structural verification. It decides nothing
  and returns 15 lines, so its tool traffic never enters the lead's context. `fork` — a sub-question
  already in the lead's context.
- **Briefing.** Fresh agents start with zero context: give the actual instruction, the file paths, the
  boundary rule that applies, what is out of scope (name the files a concurrent agent owns), and
  "done" as commands. Never "implement it based on the plan". **Restate the project's own domain
  invariants in every brief** — what an agent cannot infer from the diff: the testing discipline for
  behaviour changes, the module boundaries, where validation and shared types come from, and the
  domain semantics rules where they apply.
- **Herdr is the execution surface.** Do not dispatch implementation or review work through an
  ephemeral native subagent tool. Use `agent-spawn.sh`; observe with `agent-state.sh` and
  `agent-peek.sh`; steer with `agent-send.sh`; stop with `agent-stop.sh`. `session-start.sh` is the
  read-only recovery view at the beginning of a lead session.
- **The lead never fetches or absorbs external-source evidence on a specialist's behalf.** A Figma
  node, a URL, a screenshot, or any other externally-sourced payload a task needs is retrieved by the
  dispatched specialist itself, live, from inside its own session — never fetched by the lead and
  relayed into a brief. Proxying it bloats lead context with content the lead cannot verify and lets
  stale or unauthenticated evidence pass as if it had been checked. A role that requires live access
  to an external capability declares it in its own frontmatter (`capabilities: figma`), never in a
  name-to-capability map hard-coded in the runtime; `agent-spawn.sh`, `agent-review.sh` and
  `agent-switch.sh` each run a deterministic capability preflight on the freshly started session
  before delivering the substantive brief. A probe that fails, times out, or is silent is fail-closed:
  the brief is never delivered and the task is never recorded as dispatched — route it to a fresh
  session whose preflight succeeds instead of relaunching the same one.
- **Hand a task from its engineer to a reviewer with `scripts/agent-review.sh <task-id>
  <reviewer-role> --brief-file <path> [--engine claude|codex]`.** It reuses the SAME worktree and
  branch the engineer already has open (a fresh `agent-spawn.sh` call refuses — one task id owns one
  worktree for its whole life) and requires the current agent to be `idle`, `done`, or `blocked`
  first. It records the handoff to `$HARNESS_STATE/agent-history/<task-id>.jsonl`
  (`harness-agent-review-handoff.v1`) — the ledger a fix round's `--brief-file` and any future round
  count should read, not a native subagent's own transcript. The same command hands a task BACK from
  reviewer to engineer for a fix round, and from one reviewer to the next round's reviewer — always
  same task id, same worktree, bumped generation.
- **Model tier follows how many decisions are left in the task after briefing, not the task's topic.**
  An implementer may be wrong about how well it did the work — never about what the work is. A brief
  that still says "find out X, then choose A or B" is a planning task in implementation clothes:
  resolve it, write the answer *and its reason* into the brief, then hand it down. Never hand down
  work whose decision is *discovered* by doing it (diagnose a red CI, design a module) — scout on the
  stronger tier first — or work whose success cannot be checked by running commands. Engineers are
  told to stop and report rather than guess — never write a brief that punishes using that valve.
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
- **`design-qa` is the visual gate: it runs AFTER the code review approves and BEFORE merge** — never
  instead of a logic-tier review, and never on a PR with no named design reference. Own worktree, own
  dev server on a free port, the rendered page measured in a browser against the specific design-file
  node named in its brief, **measured numbers only**, strictly read-only: it finds discrepancies, it
  never fixes them.
- **Measure against a server YOU started from YOUR OWN worktree.** Never a shared port named in a
  brief: the main checkout wanders between branches, so on `bridgeks` one shared dev port served an
  unrelated branch for most of 2026-08-21 while every measurement against it looked entirely
  plausible — and a pre-merge backend build answers just as happily. A page-measuring script starts
  its own browser but does NOT start a dev server; pointing it at the right tree is yours. The trap
  underneath: a dev server enforcing one instance per project DIRECTORY via a lockfile, independent of
  port, cannot be started twice from one checkout — a second server needs its own worktree, which
  usually means installing dependencies in it first. Pick free ports and report which ones you used.
- **A number in a permanent comment, card or report comes from a MEASUREMENT, not from arithmetic — name what measured it.** Four false figures landed in committed comments on 2026-08-21 across two PRs and the lead's own, every one computed rather than observed: "skipped five steps" where the run showed six, a text column of "1157" that renders at 951.6 because the app's content column is 1172 and not the design's 1376, a copy called "verbatim" whose one difference was the class that got dropped. Each read as freshly verified, which is what makes a wrong number worse than none. Figures derived from a design file describe the design; write what the browser or the run reported, and say which.
- **Authority.** Engineers pushing branches and opening PRs is pre-authorized. Deploys, secret
  changes, force pushes and merging a PR are NOT: surface them to the user. Every merge to
  `{{BASE_BRANCH}}` is confirmed individually.
- **Verification before reporting.** "PR opened" is not "done": a PR-producing task needs an `APPROVE`
  verdict and the affected package's checks confirmed directly. An agent's summary describes intent,
  not outcome — and the recurring defect class here is a property enforced by its producer and merely
  trusted by its consumer.
- **Discussion mode.** An architecture ask framed as discussion ("we're not building anything yet —
  we're discussing") means an inventory of the real state plus a recommendation, in the language the
  user asked in — not dispatched agents.
- The **why** behind past decisions lives in `plan/`, `OVERVIEW.md` and `docs/decisions/`; an agent's
  private memory store holds only what has no home in the repo.

---

## The lead's protocol (session, context, spend)

Every agent reads this; only the session that is leading acts on it. Measurements: `docs/evidence.md`.

- **The lead does no file work.** Read-only one-liners with ≤~20 lines of output are the whole
  allowance; every repo-wide search, multi-file edit you have already specified, text move between
  files, script run and debug goes to `deputy` — its tool traffic dies with it and 15 lines come back.
  This is the largest single lever there is: measured 2026-08-20, tool calls and results were 68% of
  the lead transcript. Watch the split with `scripts/context-size.sh` (or the status bar, which shows
  `ctx 381k (38%) · tools 66%` and warns past 60% of the window or 55% tool traffic) — every inline
  edit and search joins the baseline that every later turn re-reads.
- **The session boundary is a card state transition, not a task.** Dividing tasks finer multiplies
  cards, PRs and review rounds for the same work; divide the SESSION instead: plan → brief written;
  brief → PR open; PR → review round closed; `APPROVE` → merged. Each transition ends with a card
  write and resumes from `INDEX.md` plus one card. Session cost grows with the SQUARE of its length —
  context grows every turn and every later turn pays for it again — so two half-length sessions cost
  about half of one long one. Analyse → write the decision and its reason into the card → **end the
  session**; the next one is pointed at the index and one card, never re-briefed.
- **Checkpoint when an agent's report arrives, not at the end of the day** — update the card (status,
  findings, `**Next:**`) BEFORE dispatching the next agent, with `scripts/checkpoint.sh`, which fails
  while the card is stale. The card write is part of receiving a report. Dead runs and interrupted
  sessions happen mid-task, and this is what bounds the loss to one agent run instead of a session.
  Hand off voluntarily
  with `scripts/handoff.sh <task>`: it checks that the card changed, that it carries a `**Next:**`
  line, that `OVERVIEW.md` has today's entry, and where the round ledger stands, then prints the
  prompt to open the next session with.
- **Every card carries a `**Next:**` line — the literal next dispatch or command**, executable by the
  next session without deriving it. "Continue T07" is not a next action.
- **Context size is diagnostic, not control flow.** `scripts/context-size.sh` and
  `scripts/agent-spend.sh` expose the cost of a long lead session, but no token threshold forces a
  handoff or context reset. Durable cards and Herdr runtime state make interruption recoverable.
- **Dispatch independent agents in ONE message.** Each dispatch/return pair is two lead turns, and
  every lead turn pays the full context re-read; three independent tasks sent one at a time buy
  nothing and cost four extra turns.

---

## Plan, overview, reports

Three artifacts, three jobs, all in git so any agent in any folder can read them. Do NOT keep the
plan in an agent's memory store: it is invisible to every other session and goes stale within a day.

- **`plan/` lives inside this project's own checkout — what we intend.** Card ids are found by
  scanning every project's `plan/` plus the harness root's own `plan/` — the one reserved exception,
  for reserved project id `jarvis`, which resolves to the harness root checkout itself rather than a
  nested clone (`project_root_path` in `scripts/herdr-runtime-lib.sh`; a nested `projects/jarvis` is
  refused as a name collision). Every other project's worktrees only ever contain what its own repo
  commits. `plan/INDEX.md` is one line per task (id,
  status, owner, dependency, note); each task gets its own card from `plan/TEMPLATE.md`, which fixes
  the header line (`Status` / `Owner` / `Depends on` / `PR` / **`Next`** / **`Owns`**) that
  `checkpoint.sh`, `handoff.sh`, `review-rounds.sh` and `owns-check.sh` all read — with goal, scope,
  the rationale behind decisions, and what "done" means. `Owns:` declares the concrete files or globs
  the card claims; `scripts/owns-check.sh` refuses when two ACTIVE cards claim the same path, catching a
  parallel double-edit at dispatch time instead of as a merge conflict. **Read `INDEX.md` first and
  open only the cards you need.** **Cross-task ordering lives in `INDEX.md`, never only inside a
  card**: a card read on its own cannot tell you it must wait for another.
- **`OVERVIEW.md` — what actually happened.** Newest first, 8–10 entries, older ones moved to
  `docs/overview-archive/YYYY-MM.md` (entry count is the rule; 60 KB / 1500 lines is the backstop).
  **Append with `scripts/overview-append.sh "title" <<'EOF' … EOF`** — it inserts after a marker it
  asserts is unique and swaps through a temp file. Never append by reading the file and editing it:
  that costs the whole file on every entry, and a half-written overwrite destroys the only record of
  what happened.
- **`reports/<task>-<agent>.md` — the full account of one delegated run.** Specialists write the long
  version there and **return ≤15 lines**: verdict, files touched, blockers, approvals needed.
  Engineers write it in their own worktree and commit it on their branch so the path resolves for the
  reviewer; report files are out of review scope. Pass a reviewer the **path as context — the diff
  stays the evidence.**
- **One language (`{{LANG}}`) for everything committed** — code, comments, docs, plan cards, reports,
  commit messages, PR titles/bodies, generated-and-committed output; not one word of another language
  enters the repository. A localized user-facing artifact routes its other-language strings into
  **gitignored local files** instead of committed source; a localization-adjacent review includes a
  grep for the other script over the branch diff.

Keeping these current is part of finishing a task: a task is not done while its card says
`in-progress`. The card is written at every checkpoint, not at the end — a session that ends without
one takes its state to the grave, and the next session pays to rediscover it.

### Task ids

- **Every new card is minted by `scripts/new-task.sh <slug>`**, never by hand and never by a
  subagent: the lead runs the script and hands the finished id down. It produces
  `plan/<YYMMDD-HHMM>-<NNN>-<slug>.md` — the minute-granular session prefix is collision-free with no
  cross-session coordination, `<NNN>` counts within the prefix from `001` — creates the card from
  `plan/TEMPLATE.md`, adds its `INDEX.md` row, regenerates the dashboard, and **commits, all in one
  step**, so a claim is visible to every other session and worktree the moment it is made. It needs
  installed dependencies, so install in a fresh worktree first.
- **If the project already carries ids in an older shape, freeze them** — never renamed, never reused.
  They are the historical record; there is no migration and no sunset. **Any script or matcher reading
  plan ids MUST accept both shapes** — handling only one is a bug, not an acceptable simplification.
- **`plan/` stays flat** — no per-session directories; dependencies are cross-session by nature.
- **`scripts/plan-check.sh` fails on any `plan/*.md` untracked by git or missing from `plan/INDEX.md`**,
  and runs both as **its own CI job** (so no earlier red step can mask it) and in the pre-commit hook.
  The hook is best-effort — hooks are dead in a checkout with no installed dependencies — and CI can
  only ever see the INDEXED half, because an untracked file never reaches another machine. Committing
  at claim time is what actually closes the gap.

---

## Shell discipline (permission-friendly commands)

- NEVER use `&`, `(subshells)`, `;` chains, `||`, or `$( )` in a shell call. One simple command per
  call; `&&` between two allowlisted commands is OK.
- Long-running processes (dev server, component workbench) — a backgrounded run with output polling,
  never `(cmd &)`.
- No `sleep N && curl` chains — background the server, curl in a separate call.

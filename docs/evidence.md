# Why each rule exists — the measurements

Every rule in `RULES.md` came from a number or an incident, not from taste. Keep this file with the
harness: a rule whose reason is known survives an argument, and a rule without one gets "optimised"
away by the next person who finds it inconvenient.

All figures are token-cost equivalents computed from local session transcripts on 2026-08-19 and
2026-08-20 (Opus 5 at $5/$25 per Mtok, Sonnet 5 at its intro $2/$10, cache write ×1.25, cache read
×0.1). On a subscription plan the real unit is a share of the weekly limit; the ranking is identical.

## The lead session is the most expensive thing in the pipeline

One day, one repo: **$682 total, of which the lead session was $309 (45%)** — more than all reviews
and all engineer runs combined. It read **493,455 tokens of context per message** across 860
messages, and **$212 of its $309 was the session re-reading its own conversation.**

The lever is not the model. It is session length, plus what the lead does inline: every file edit and
search performed in the planning conversation joins the baseline that every later turn re-reads.
Hence: analyse → write the card → end the session; and do file work in a subagent.

This is also what makes the committed `plan/` structure pay: ending a session is only cheap if the
state survives it. A fresh session costs `INDEX.md` plus one card — about 1k tokens against a
740k-token conversation.

## Session length is the variable, not task size — and the checkpoint is what makes it safe

Second day, second measurement: **$230.52 total, lead $125.21 (54.3%)** across 568 messages, at
**275,663 cache-read tokens per message**, of which **$78.29 was the session re-reading itself**. The
lead transcript was **68.2% tool calls and results** — file work done in the conversation rather than
in a subagent — against 17.6% user messages and 14.2% assistant replies.

The tempting fix — cut *tasks* smaller so each fits one session — is wrong. Each task carries a card,
a PR and at least one review round at $10–15, so ten small PRs instead of three buys seven extra
reviews for the same code. The only task-level split that pays is *one PR, one concern*, and it pays
by removing re-reads, not by shrinking units.

Session length is the real variable, and the arithmetic is not subtle: context grows monotonically
within a session and every later turn pays for all of it again, so cost is roughly **quadratic in
session length**. One session of n turns costs ≈ g·n²/2; k sessions of n/k turns cost ≈ g·n²/(2k). The
same arithmetic is behind both days' "session re-reading itself" figures.

Which also explains why resuming felt expensive and is not: resuming *from a card* is O(1) — the index
plus one card. Resuming *the conversation* is O(n) on every remaining turn. A usage limit is therefore
a handoff signal, never a pause.

The gap that actually hurt was timing. `handoff.sh` and the 400k threshold were both framed as
end-of-day rituals, while limits and dead agent runs happen mid-task — and whatever was not on the
card at that moment died with the conversation. So the card write moved from *closing a session* to
*receiving a report*, with `scripts/checkpoint.sh` refusing to pass while the card is stale, and
`**Next:**` became a required card field so a resuming session gets an instruction rather than a topic.

## Review cost is reading, not finding

Same day: **11 review runs, $200**, median 183 messages per run. Per-review context was never the
problem — 86k–165k cache-read per message, three to five times *below* the lead.

The cost was rounds. **One PR took five review rounds, ≈$112 of the $200.** That PR carried 5,020
diff lines across three unrelated concerns (feature UI, a shared component, and 309 lines of shell
that killed processes), and **both blockers of round 2 lived in 190 lines of the shell script** — not
in the feature the PR was named after. Every round re-read all 5,020 lines to find them.

Hence: one PR one concern; a fix round reads only the delta; a reviewer never sweeps the repo; and the
round ceiling is two.

## Tiering by topic is wrong; tiering by remaining decisions is right

A review split by *diff size* would have sent a four-class-name change to the cheap tier. That change
was to a shared button primitive every screen renders — the blast radius, not the diff, decides.

Symmetrically, a task that *looks* like frontend typography was actually a planning task: it asked the
implementer to determine what the design specified and then choose between two fixes. Resolve that
first and the same task becomes safe for a cheaper tier. **The tier question is: how many decisions
are left after briefing?**

## The logic-tier reviewer's model changed under it

Observed on bridgeks: the logic-tier reviewer ran on opus at the time the tiering rule above was
written, moved to fable from 2026-08-21, and was moved BACK to opus at effort `xhigh` on 2026-08-26
(commit `37cfb3c`, "logic-tier reviewers on opus/xhigh"). The tiering logic (by decisions remaining,
not by topic) did not change through any of it - only the model filling the tier did.

Two lessons, and the second is the more useful one. First: a stale mention of a model name in an
older note or card is history, not the current configuration. Second: on 2026-08-26 the sentence
"fable since 2026-08-21" was still sitting in the project's own pipeline decision doc five days
after it stopped being true, and it propagated from there into this folder during the sync before a
frontmatter check caught it. A model tier is the fastest-rotting fact in a harness. Read it from the
agent definitions' `model:`/`effort:` lines, which the runtime actually uses, and treat any prose
that names a tier as a claim with an expiry date.

## The recurring defect class

Across two projects, the defects that reached review and mattered had one shape: **a property
enforced by whoever produces a value and merely trusted by whoever consumes it.** A guard trusting a
token's self-reported expiry; a rate-limit key that was not actually per-client; a shell function that
checked ownership in one loop and not in the escalation loop beside it; a rate ceiling doing two jobs.

Two consequences are baked into the harness: reviewers are told to hunt that shape specifically, and
"the engineer said the checks passed" is never accepted as verification.

## Tests are evidence only if they have been seen failing

A fidelity suite asserted a value on one variant of three and passed while two variants were wrong.
A test double manufactured a crash the real runtime never produced, and a commit message written from
the double's behaviour overstated the severity of a real but lesser bug.

Hence: TDD ordering is a rule, and any assertion that matters is mutation-verified — flip the value,
watch that assertion fail, then flip it back.

## The rules file is a fixed cost on every run

Every agent reads the project's rules file on every run. Ours grew 32% in a day and reached 40 KB
before being cut to 26 KB by moving two large rationale sections into `docs/decisions/` — with the
rule lists left behind in full. Adding "just one more paragraph of context" to that file is a charge
levied on every future run; put the paragraph in `docs/decisions/` and link it.

## Numbers that came from computing instead of measuring

Observed on bridgeks, 2026-08-21: **four false figures landed in committed comments across two PRs**
(one of them the lead's own), every one computed rather than observed — "skipped five steps" where
the run showed six, a text column reported as "1157" that actually rendered at 951.6 because the
app's content column measured 1172px and not the design file's 1376px, a copy labelled "verbatim"
whose one difference was a dropped class. Each read as freshly verified, which is what makes a wrong
number worse than none. The rule this produced: a number in a permanent comment, card, or report
comes from a measurement, not from arithmetic, and the writer names what measured it. A figure
derived from a design file describes the design; write what the browser or the run reported, and say
which instrument.

## The shared-port trap

Observed on bridgeks: `localhost:3003` served an unrelated branch for most of 2026-08-21, and every
measurement taken against it that day looked entirely plausible — nothing about the numbers
themselves signalled the mismatch. The cause was structural, not a one-off mistake: `next dev`
enforces one server per project directory via a lock file, independent of port, so a checkout that
already has a server running cannot start a second one — the only way to get an isolated server is a
worktree of one's own. The rule this produced: measure only against a server started from your own
worktree, never a shared port named in a brief, and state which port and which commit SHA were
measured.

## The round ledger counts what ran, not what was written down

Observed on bridgeks, 2026-08-20: a card recorded **one** review round for a PR that had actually had
**four**. The rule addressed to the lead — checkpoint before dispatching the next agent — was itself
the thing skipped under context pressure, which is exactly the failure mode a rule written for a
tired lead needs to survive. The fix was to stop trusting the card's own count: the round ledger
script reads each card's declared PR number, counts reviewer runs against that PR **in the local
transcripts**, compares that against the card's declared round headings, and exits non-zero at or
past the ceiling — so the ledger is derived from what actually ran, not from what a session claimed
it did.

## A near miss: a stale "this is always red" note

Observed on bridgeks: a note that CI was permanently red on a particular check (`pnpm lint:deps`)
went stale after master started passing it, and the stale note nearly waved a real regression on a
PR through as "the usual red" — the regression looked identical to the long-familiar false failure
until someone re-measured the check against `origin/master` in the same worktree instead of trusting
the note. The general lesson: a "this always fails, ignore it" note is a claim with an expiry date,
not a permanent fact — re-verify it against the current base branch before relying on it to wave
anything through.

## Frozen legacy identifiers, worked example

Observed on bridgeks: an older task-id scheme (`T01`–`T48`, plus lettered sub-ids like `T16a`–`T16e`)
is frozen permanently rather than migrated — roughly **1,400 references** to those ids exist across
the repo (cards, commits, PR titles, code comments), there is no migration path, and there is no
planned sunset. A newer, collision-free id scheme was introduced for all new work instead of trying
to renumber the old one. The general lesson: when an identifier has accumulated enough references
that renaming it would itself become the expensive, error-prone change, the cheaper and safer move is
to freeze it and let a second scheme coexist permanently — never renamed, never reused, accepted as
a permanent two-scheme state rather than a migration debt.

## What has NOT been proven

- `mechanical-reviewer` has **zero runs** as of 2026-08-20. The tier split is measured; this agent's
  behaviour is not. Watch its first escalations closely.
- The delta-review and round-ceiling rules were written on 2026-08-20 and have not yet run a full
  cycle. They trade money for a narrower reading — which shifts responsibility onto the brief. If a
  brief names the wrong previous tip or omits a finding, a delta review will faithfully verify the
  wrong thing.
- The handoff threshold (~400k read per lead message) is two days' observation, not a tuned figure.
- **`scripts/checkpoint.sh` and the `**Next:**` field are new on 2026-08-20 and have not survived a
  full task yet.** The failure they are built for — a session dying mid-task with its state only in
  the conversation — has happened; that they prevent it is an expectation, not a measurement.
- The quadratic session-cost claim is arithmetic over an observed growth pattern, not a controlled
  comparison. Nobody has run the same task twice, once long and once split, and priced both.

#!/usr/bin/env bash
# The round ledger: review rounds per task, counted from what actually RAN, cross-checked against
# what the plan card recorded.
#
# Why it counts runs and not just cards: the round ceiling was a rule addressed to the lead, and the
# lead is also told to end its session early — so nothing remembered the count. Cards are supposed to
# record each round, but observed on bridgeks 2026-08-20: a card showed one round for a PR that had
# had five reviewer runs. A ledger that trusts the write-up inherits the write-up's optimism.
#
# Two properties this script must never lose, both learned the hard way on bridgeks (2026-08-20):
#
#   1. WHERE the transcripts live is a property of the REPOSITORY, not of the directory you happen
#      to be standing in. The lookup must not derive its filter from the basename of the checkout the
#      script file sits in — run from a worktree at `.claude/worktrees/<name>/scripts/review-rounds.sh`
#      and that filter becomes `<name>`, which appears in no transcript path, so `ran` silently reads
#      0 for every task. Agents and humans both work under project worktrees routinely, so the broken
#      path is the normal path. The main worktree is resolved via `git rev-parse --git-common-dir`,
#      and the project directory is matched EXACTLY — a substring test would also let a repo named
#      `myproject` swallow a sibling `myproject-ui-kit` project's reviewer runs.
#
#   2. It must FAIL LOUDLY rather than report zero when it cannot look. A guardrail that cannot tell
#      "no rounds ran" from "I could not see the rounds" inverts into a green light. The enumerated
#      lookup failures each exit 2 naming the path they could not read — but enumeration is exactly
#      what went wrong the first time, so the real guarantee is the single invariant below: a count
#      is reportable ONLY if at least one subagent record was found AND parsed. Every other zero,
#      including causes nobody has thought of yet (a renamed `subagents/`, a moved layout), fails
#      that one check rather than needing its own branch.
#
#   3. The CARD side has the same duty as the transcript side, and used to shirk it (observed on
#      bridgeks 2026-08-25): `plan/T[0-9][0-9]-*.md` matched neither the frozen `T16a`-`T16e` cards
#      (one of which was the only declarer of PR #32) nor the session-prefixed ids `new-task.sh`
#      mints — and it printed `Cards: 23` as though 23 were every card there is. A count that omits
#      what it could not match, while reading as complete, is the same inversion as reporting
#      `ran = 0` for a lookup that failed. So plan/ is now enumerated TOTALLY: every `plan/*.md` is
#      classified as a card, a named non-card, or a SKIP that is printed out loud, and the id
#      matcher accepts BOTH permanently-coexisting shapes: the frozen legacy `T<nn>[<letter>]` and
#      the session-prefixed `<YYMMDD-HHMM>-<NNN>`. Handling only one shape is a bug, not a
#      simplification, in any project that adopted this scheme onto pre-existing legacy ids.
#
# Exit codes: 0 = under the ceiling · 1 = at/over the ceiling for some task · 2 = could not look.
#
# Card convention (still required — it is what a fresh session reads first):
#     ## Review round N (<reviewer>, <date>): <VERDICT>
#     ## Fix round N (<date>): <one line>
#
# Usage: scripts/review-rounds.sh [T02]
# Tests: scripts/test/review-rounds.test.sh, if the target project has ported one — # project-specific: wire into your test runner if you keep one

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The MAIN worktree's root — not $PWD, not where this file sits. `--git-common-dir` points at the
# one shared `.git` directory for every linked worktree, so its parent is the main checkout.
MAIN_ROOT=""
if COMMON_DIR="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  :
else
  # git < 2.31 has no --path-format; the plain form is relative to the -C directory.
  COMMON_DIR="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$COMMON_DIR" ] && [ "${COMMON_DIR#/}" = "$COMMON_DIR" ]; then
    COMMON_DIR="$ROOT/$COMMON_DIR"
  fi
fi
if [ -n "$COMMON_DIR" ] && [ -d "$COMMON_DIR" ]; then
  MAIN_ROOT="$(cd "$COMMON_DIR/.." && pwd)"
fi

WANT="${1:-}" ROOT="$ROOT" MAIN_ROOT="$MAIN_ROOT" \
PROJECTS="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}" \
CEILING="${REVIEW_ROUND_CEILING:-2}" python3 - <<'PY'
import json, os, glob, re, sys, traceback
from collections import Counter

root      = os.environ["ROOT"]
main_root = os.environ["MAIN_ROOT"]
want      = os.environ["WANT"]
projects  = os.environ["PROJECTS"]
ceiling   = int(os.environ["CEILING"])


def cannot_look(problem, remedy):
    """Exit 2. Never 0-and-carry-on: a lookup that failed must not read as an all-clear."""
    print(f"review-rounds: cannot count reviewer runs — {problem}", file=sys.stderr)
    print(f"review-rounds: {remedy}", file=sys.stderr)
    print("review-rounds: refusing to report `ran = 0`, which would read as 'no rounds have run'.",
          file=sys.stderr)
    raise SystemExit(2)


def crash_is_also_cannot_look(exc_type, exc, tb):
    """Any unhandled exception exits 2, never 1.

    Exit 1 is IN-BAND: it means "at or over the ceiling for some task", and both callers act on it by
    testing `-ge 2`. So a Python traceback — which exits 1 — took the else branch, printed line 2 of
    the traceback where the ledger row belongs, skipped the `problems` increment, and left
    `checkpoint.sh` announcing `Clear to dispatch.` over a completely blind ledger (B1, round 2).
    That is the inversion this whole script exists to remove, reached through the one door the
    enumerated causes did not cover.

    So this is deliberately the LAST line of defence rather than one more enumerated cause: the
    `isinstance` guard below fixes the record shape that was actually found, and this fixes the class
    of "something nobody predicted went wrong", which is what the F1 invariant's comment claimed and
    did not deliver. `os._exit` because raising SystemExit from an excepthook cannot set the exit
    code — the interpreter has already chosen 1 by the time we are called. Buffered stdout is
    deliberately NOT flushed: a half-printed table is exactly what no caller should be able to read.
    """
    traceback.print_exception(exc_type, exc, tb)
    print(f"review-rounds: cannot count reviewer runs — crashed: {exc_type.__name__}: {exc}",
          file=sys.stderr)
    print("review-rounds: this is a bug in review-rounds.sh; the traceback above is the report.",
          file=sys.stderr)
    print("review-rounds: refusing to report `ran = 0`, which would read as 'no rounds have run'.",
          file=sys.stderr)
    sys.stderr.flush()
    os._exit(2)


sys.excepthook = crash_is_also_cannot_look


def require(checks):
    """One exit point for every enumerated way of being blind. A newly understood cause is a row
    here, not another `if` buried in the flow — and the causes nobody enumerated are caught by the
    parsed-a-record invariant further down instead of slipping through as a zero."""
    for ok, problem, remedy in checks:
        if not ok():
            cannot_look(problem, remedy)


# --- resolve the transcript directory for THIS repository, independent of $PWD ---------------
require([
    (lambda: bool(main_root),
     f"could not resolve the main git worktree from {root!r}",
     "run this from inside the project's repository (or one of its worktrees)."),
    (lambda: os.path.isdir(projects),
     f"transcript root {projects!r} does not exist or is not a directory",
     "set CLAUDE_PROJECTS_DIR to where Claude Code keeps ~/.claude/projects."),
    (lambda: os.access(projects, os.R_OK | os.X_OK),
     f"transcript root {projects!r} is not readable",
     "check its permissions."),
])

# Claude Code files a session under ~/.claude/projects/<encoded cwd>. Encoding replaces the path
# separators (and, in some versions, every other non-alphanumeric) with '-'. Try both, EXACTLY:
# substring matching used to make a repo named `bridgeks` also swallow `bridgeks-ui-kit`.
candidates, seen = [], set()
for name in (re.sub(r"[^A-Za-z0-9]", "-", main_root), main_root.replace(os.sep, "-")):
    if name not in seen:
        seen.add(name)
        candidates.append(os.path.join(projects, name))

project_dir = next((c for c in candidates if os.path.isdir(c)), None)
require([
    (lambda: project_dir is not None,
     f"no transcript directory for {main_root!r} under {projects!r}; looked for "
     + " and ".join(repr(os.path.basename(c)) for c in candidates),
     "if transcripts live elsewhere, point CLAUDE_PROJECTS_DIR at them."),
    (lambda: bool(project_dir) and os.access(project_dir, os.R_OK | os.X_OK),
     f"transcript directory {project_dir!r} is not readable",
     "check its permissions."),
])

# --- what actually ran: reviewer subagents, grouped by the PR number in their description ---
# Only inside project_dir, only the exact layout — no globbing across sibling projects.
pattern  = os.path.join(project_dir, "*", "subagents", "*.meta.json")
metas    = sorted(glob.glob(pattern))
sessions = len(glob.glob(os.path.join(project_dir, "*", "subagents")))

observed = {}          # PR number -> list of indices into `runs`
runs     = []          # one entry per reviewer run: (set of PR numbers named, description)
parsed = unreadable = 0
for meta in metas:
    try:
        m = json.load(open(meta))
        # Valid JSON is not the same as a usable record. `null`, `[]` and `"str"` all parse, and
        # `m.get(...)` below then raises — which used to exit 1, i.e. the ceiling's own code. A
        # mis-shaped record is a record we could not read, so it belongs in the arm that already
        # says so, and one bad file no longer takes a whole directory of good ones down with it.
        if not isinstance(m, dict):
            raise ValueError(f"record is {type(m).__name__}, not a JSON object")
    except Exception:
        unreadable += 1
        continue
    parsed += 1
    if "reviewer" not in (m.get("agentType") or ""):
        continue
    desc = m.get("description") or ""
    prs = set(re.findall(r"(?:PR|pr|#)\s*#?(\d{1,4})", desc))
    runs.append((prs, desc))
    for n in prs:
        observed.setdefault(n, []).append(len(runs) - 1)

# THE invariant — the whole "fail loudly, never zero" requirement in one check. A zero is only
# reportable if a record was actually read; anything else is a lookup that failed, whether or not
# its cause was enumerated above. This is what covers a renamed or relocated `subagents/`, an empty
# project directory, and every unparseable record — the causes that each used to need their own
# branch, and the ones that have not happened yet.
if parsed == 0:
    if unreadable:
        cannot_look(
            f"all {unreadable} subagent record(s) matching {pattern!r} were unreadable",
            "check their permissions, or whether the transcript format changed.",
        )
    cannot_look(
        f"read no subagent record at all — {pattern!r} matched {len(metas)} file(s), and "
        f"{sessions} 'subagents' directory/ies exist under {project_dir!r}",
        "either the transcript layout changed (find what replaced 'subagents/'), or no subagent has "
        "ever run for this repository; either way there is nothing here to verify a count against.",
    )

# --- which files in plan/ are task cards, and which were skipped --------------------------------
# Two id schemes coexist PERMANENTLY (CLAUDE.md, "Task ids"): the frozen legacy `T<nn>[<letter>]`
# (`T07`, `T16a`) and the session-prefixed `<YYMMDD-HHMM>-<NNN>` minted by scripts/new-task.sh
# (`260824-1432-001-asset-photo-pool.md`). Matching only one of them is a bug, not a simplification.
#
# But the glob was never the real defect — `Cards: 23` was. So the enumeration is total: plan/ is
# listed in full and every file lands in exactly one bucket, and the footer prints all three counts
# plus the names of anything skipped. The next naming variant then shows up as a named SKIP instead
# of silently shrinking a number that still looks like a total.
CARD_ID = re.compile(r"^(T\d{2}[a-z]?|\d{6}-\d{4}-\d{3})-.+\.md$")
# Files that live in plan/ and are deliberately not cards. Anything NOT here and not matching
# CARD_ID is reported, never quietly dropped — that is the whole point of the classification.
NON_CARDS = {"INDEX.md", "TEMPLATE.md"}

plan_dir = os.path.join(root, "plan")
plan_md  = sorted(glob.glob(os.path.join(plan_dir, "*.md")))
cards, non_cards, skipped = [], [], []
for path in plan_md:
    base = os.path.basename(path)
    m = CARD_ID.match(base)
    if m:
        cards.append((m.group(1), path))
    elif base in NON_CARDS:
        non_cards.append(base)
    else:
        skipped.append(base)
if not cards:
    sys.exit("no task cards in plan/")

# The PR must be DECLARED on its own line in the documented form (plan/TEMPLATE.md, CLAUDE.md):
#
#     PR: #123            or            PR: none yet
#
# and not merely mentioned. Cards cross-reference each other's PRs constantly and their prose wraps,
# so `plan/T21-post-login-return-destination.md` has a body line that BEGINS "PR #32's pre-fix tip
# (`804d1eb`)". With the colon optional, that read as T21 declaring #32 — T21 inherited another
# card's two reviewer runs and displayed a CEILING it had never reached. The colon is the
# discriminator between a declaration and prose, so it is mandatory, and the token right after it
# has to be the number or an explicit `none`.
#
# A `PR:` line that satisfies neither is REPORTED on the row rather than read as "no PR". A card that
# tried to declare and got the format wrong is the least excusable place for a silent zero — and
# there is one live: plan/T14-ui-kit-shadow-token.md declares its PR as a GitHub URL, which the old
# matcher missed in complete silence.
#
# `PR_LINE` deliberately matches a SUPERSET: the declaration itself plus any `PR:` line that is
# merely indented or bulleted (`  PR: #24`, `- PR: #24`). Those used to match nothing at all — they
# were neither parsed nor reported, which contradicts the rule above in the one direction that is
# invisible. Group 1 captures whatever precedes the marker; empty means a real declaration, anything
# else means "you meant to declare this and it is not on its own line". The bullet alternative
# requires whitespace after the marker so that `**PR:**` (a real form, used by cards) still reads as
# column-zero rather than as a `*` bullet.
PR_LINE = re.compile(r"(?m)^([^\S\n]*(?:[-*+>][^\S\n]+)?)\**PR\**:\**[^\S\n]*(.*?)[^\S\n]*$")
PR_NUM  = re.compile(r"^#(\d{1,4})(?!\d)")
PR_NONE = re.compile(r"^none\b", re.IGNORECASE)

# Every card is measured, so the attribution footer describes the repository rather than the
# filtered view; only the rows matching `want` are printed, and only printed rows set `breached` —
# `review-rounds.sh T07` must not exit non-zero because some other task is over its ceiling.
rows = []
for tid, card in cards:
    text = open(card, encoding="utf-8").read()

    recorded = len(re.findall(r"(?m)^## +Review round \d+", text))
    fixes    = len(re.findall(r"(?m)^## +Fix round \d+", text))

    declared_nums, malformed, offside = [], [], []
    for lead, tail in PR_LINE.findall(text):
        if lead:
            # Indented or bulleted: reported, never accepted. Accepting it would make the anchor
            # meaningless again, and ignoring it is the silent miss this part of T27 is about.
            offside.append((lead + "PR: " + tail)[:44])
            continue
        mnum = PR_NUM.match(tail)
        if mnum:
            declared_nums.append(mnum.group(1))
        elif not PR_NONE.match(tail):
            malformed.append(tail)
    pr  = declared_nums[0] if declared_nums else None
    ran = len(observed.get(pr, [])) if pr else 0

    effective = max(recorded, ran)
    if effective > ceiling:
        state = f"OVER CEILING by {effective - ceiling} — stop dispatching full reviews"
    elif effective == ceiling:
        state = "CEILING — the lead reads the findings itself now"
    elif effective == ceiling - 1:
        state = "one round left"
    else:
        state = "ok"

    notes = []
    if malformed:
        shown = ", ".join(repr(t[:44]) for t in malformed[:2])
        extra = f" (+{len(malformed) - 2} more)" if len(malformed) > 2 else ""
        notes.append(f"unparseable `PR:` line: {shown}{extra} — write `PR: #<n>` or `PR: none yet`")
    if offside:
        shown = ", ".join(repr(t) for t in offside[:2])
        extra = f" (+{len(offside) - 2} more)" if len(offside) > 2 else ""
        notes.append(f"indented/bulleted `PR:` line: {shown}{extra} — the declaration must start "
                     "the line")
    if len(set(declared_nums)) > 1:
        uniq = ", ".join("#" + n for n in dict.fromkeys(declared_nums))
        notes.append(f"declares more than one PR ({uniq}) — the first is used")
    if pr and ran != recorded:
        notes.append(f"card says {recorded}, transcripts say {ran} — fix the card")
    elif not pr and not (malformed or offside):
        # Only when the card is genuinely silent about its PR. `T14` used to render BOTH
        # "unparseable `PR:` line: 'https://…'" and "no `PR: #n` line in the card" in one row, which
        # contradict each other: one says the line is there and wrong, the other says it is absent.
        # The unparseable note already tells the reader what to write.
        notes.append("no `PR: #n` line in the card — add one so rounds can be counted")
    for note in notes:
        state += f"  [{note}]"

    rows.append((tid, pr, recorded, ran, fixes, state, effective))

# Session-prefixed ids are 15 characters where `T07` is 3, so the id column is sized from the data
# rather than pinned at 6 — a fixed width silently ran the columns together the first time a
# `260824-1432-001` row appeared.
idw = max(6, max(len(r[0]) for r in rows))
print(f"{'task':{idw}} {'PR':>5} {'recorded':>9} {'ran':>4} {'fixes':>6}  state")
breached = False
for tid, pr, recorded, ran, fixes, state, effective in rows:
    if want and tid != want:
        continue
    if effective >= ceiling:
        breached = True
    print(f"{tid:{idw}} {('#'+pr) if pr else '—':>5} {recorded:>9} {ran:>4} {fixes:>6}  {state}")

print()
# Say what was read, so a zero is legible as a zero and never as a silent miss. Reaching here means
# at least one record was parsed, which is what entitles the wording below to the word "verified".
if not runs:
    print(f"Transcripts: 0 reviewer runs — a verified zero: {parsed} record(s) read, none from a "
          "reviewer, in")
    print(f"  {project_dir}")
else:
    print(f"Transcripts: {len(runs)} reviewer run(s) read from")
    print(f"  {project_dir}")
    # Where every reviewer run ended up. A run reaches a row only if its description names a PR AND
    # some card declares that PR, so `ran` is a LOWER BOUND, not a measurement.
    declared = {r[1] for r in rows if r[1]}
    in_rows  = {i for pr in declared for i in observed.get(pr, [])}
    no_pr    = sorted(desc for prs, desc in runs if not prs)
    # MEASURED from the runs, not derived by subtraction. It used to be
    # `len(runs) - len(no_pr) - len(in_rows)`, which made the check below compare three terms with
    # their own subtraction — true for every input, so it was dead code that read like a guard.
    undeclared = len([d for prs, d in runs if prs and not (prs & declared)])
    # What this check is, stated exactly, because the first version of this comment overclaimed and
    # the overclaim is the defect class this whole file exists to remove:
    #
    #   * The three buckets are a PARTITION of `runs` by construction — a run either names no PR, or
    #     names at least one declared PR, or names only undeclared ones — so with the definitions as
    #     they stand the identity holds for every possible input and this branch cannot be reached by
    #     any data. It is not a runtime cross-check and must not be described as one.
    #   * Its exit code is a DIAGNOSTIC for an EDIT that breaks one of the three bucket definitions:
    #     M24 mis-measures `undeclared` with the guard intact, and the guard fires — its red lines
    #     are `exit 2` where a table was expected. That is the extent of what is demonstrated.
    #   * No mutant shows the guard is worth anything BEYOND what the suite already catches, and the
    #     measurement says the opposite. M24b mis-measures the same bucket AND deletes the guard, so
    #     it cannot die at the guard; it dies at test 14's footer-partition assertion
    #     (`review-rounds.test.sh:377`, expectation built at :372 — `footer partition wrong
    #     (row sum=10)`) and at nothing else.
    #     Read plainly, that KILLED verdict measures test 14 catching the mis-accounting on its own.
    #     So the guard converts a wrong-but-plausible footer into a named exit-2 diagnosis, which is
    #     worth having on its own terms — but do not claim it as coverage the suite lacks.
    #   * It does NOT stop a half-written table from being read. Measured on this repo's Python
    #     3.13.9: CPython flushes `sys.stdout` before it calls `sys.excepthook`, so a failure raised
    #     after the table has been printed emits the table regardless of `os._exit`. An earlier
    #     version of this comment claimed the opposite and cited test 12, which only appears to show
    #     it because it injects its crash BEFORE the header print. The exit code, not the absence of
    #     output, is what protects callers: `checkpoint.sh` and `handoff.sh` both test `-ge 2` and
    #     print the whole thing as a failure. `cannot_look` is therefore the right exit — a named
    #     diagnosis and a remedy beat a traceback, and it buys nothing to avoid it.
    if len(in_rows) + len(no_pr) + undeclared != len(runs):
        cannot_look(
            f"attribution buckets do not partition the {len(runs)} reviewer run(s): "
            f"{len(in_rows)} attributed + {len(no_pr)} with no PR + {undeclared} undeclared",
            "this is a bug in review-rounds.sh's attribution accounting — do not trust the table "
            "above it.",
        )

    # T27, finding 3: the ACCOUNTING above was right and the old CROSS-CHECK was wrong. `in_rows`
    # counts distinct RUNS; the `ran` column sums ATTRIBUTIONS, and one run occupies several rows
    # whenever it names several declared PRs or a PR is declared by several cards. Two different
    # quantities were never going to reconcile — a real run printed `16 of 27` beneath a column
    # summing to 18 — and the old test could not see it because its fixture gave every PR one card
    # and every run one PR, so the difference could not arise. Both figures are printed and labelled
    # now, and the gap is EXPLAINED, which is the only version of this that stays true as the data
    # changes.
    row_sum    = sum(len(observed.get(r[1], [])) for r in rows if r[1])
    per_pr     = Counter(r[1] for r in rows if r[1])
    multi_card = sorted((p for p, c in per_pr.items() if c > 1), key=int)
    multi_pr   = [d for prs, d in runs if len(prs & declared) > 1]
    # EVERY figure in this footer is repository-wide, including the row-sum: `row_sum` adds up the
    # `ran` column of all rows, not of the rows that got printed. Under a task filter the table is
    # one row, so an unscoped "the `ran` column sums to 41" reads as a claim about that row and is
    # off by an order of magnitude. `handoff.sh` documents the filtered invocation, so that is the
    # form a session actually sees — both lines carry the same marker or neither means anything.
    scope = " (all cards, not just the row above)" if want else ""
    all_cards = " over all cards, not just the row above," if want else ""
    print(f"Attribution{scope}: {len(in_rows)} of {len(runs)} run(s) reach a row; {len(no_pr)} name "
          f"no PR number, {undeclared} name a PR no card declares.")
    print(f"  The `ran` column{all_cards} sums to {row_sum} — attributions, not runs: a run is "
          "counted once per row it reaches.")
    if row_sum != len(in_rows):
        why = []
        if multi_card:
            why.append(f"{len(multi_card)} PR(s) declared by more than one card ("
                       + ", ".join("#" + p for p in multi_card[:5])
                       + (", …" if len(multi_card) > 5 else "") + ")")
        if multi_pr:
            why.append(f"{len(multi_pr)} run(s) naming more than one declared PR")
        print(f"  The {row_sum - len(in_rows)} extra attribution(s) come from: "
              + ("; ".join(why) if why
                 else "a source this script does not model — treat both figures as suspect")
              + ".")
    print("  `ran` is therefore a LOWER BOUND on reviews that ran, not a measurement.")
    if no_pr:
        shown = ", ".join(repr(d[:52]) for d in no_pr[:5])
        more = f" (+{len(no_pr) - 5} more)" if len(no_pr) > 5 else ""
        print(f"  Names no PR: {shown}{more}")
if unreadable:
    print(f"  ({unreadable} subagent record(s) unreadable and skipped)")
# Not a bare count: the classification is what makes the figure standable-behind. `Cards: 23` read
# as "23 cards exist" when five more did and one of them held the only declaration of PR #32.
print(f"Cards: {len(cards)} task card(s) — all {len(plan_md)} plan/*.md file(s) classified: "
      f"{len(non_cards)} non-card ({', '.join(non_cards) if non_cards else 'none'}), "
      f"{len(skipped)} skipped.")
print(f"  in {plan_dir}")
if skipped:
    warn = ("  !! SKIPPED and therefore NOT counted above: "
            + ", ".join(skipped[:8]) + (f" (+{len(skipped) - 8} more)" if len(skipped) > 8 else "")
            + " — no known task-id shape (`T<nn>[<letter>]` or `<YYMMDD-HHMM>-<NNN>`). Every figure "
              "above is a lower bound until these are renamed or the matcher is widened.")
    print(warn)
    print(warn.strip(), file=sys.stderr)
print()
print(f"Ceiling: {ceiling} review rounds per task. Past it, the lead reads the findings itself and either")
print("dispatches a TARGETED check of one hunk or takes the decision to the user — a third full review")
print("re-reads what two reviewers already read. Every review brief must state \"round N of "
      f"{ceiling}\" and name")
print("the previous round's tip; if the card does not record N, fix the card before dispatching.")

raise SystemExit(1 if breached else 0)
PY

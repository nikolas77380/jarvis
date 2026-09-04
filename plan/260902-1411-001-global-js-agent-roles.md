# 260902-1411-001 — global-js-agent-roles

**Status:** in-review · **Owner:** deputy · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: #4 — https://github.com/nikolas77380/jarvis/pull/4
**Next:** hand PR #4 back to the engineer for the round-1 fixes with
`scripts/agent-review.sh 260902-1411-001 deputy --brief-file <path>`, briefing blockers 1-2 and
should-fix 3-8 from `reports/260902-1411-001-reviewer.md` (fix round reviews the delta from tip
`e24cef9`; round 2 of 2 is the last one available).

## Goal

Upgrade Jarvis's global JavaScript agent set from the stronger project-local Yavo roles without
making the shared harness depend on Yavo. This gives every onboarded project reusable NestJS and
Next.js engineering/review roles plus evidence-driven npm dependency research.

The user chose five roles, adaptation rather than verbatim copying, npm-only research, read-only
researcher authority, and the existing Yavo model tiers. Yavo's local roles remain intact because
project invariants belong in project-local overrides.

## Scope

**Owns:** `agents/nestjs-engineer.md`, `agents/nestjs-reviewer.md`,
`agents/nextjs-engineer.md`, `agents/nextjs-reviewer.md`, `agents/deps-researcher.md`, `RULES.md`,
`agents/orchestrator.md`, `tests/role-resolution.test.sh`

Adapt the five roles from `projects/yavo/agents/` into global roles. Preserve stack-specific
discipline, bounded review, safety checks, TDD expectations, App Router boundaries, and npm package
evaluation. Remove Yavo repository names, paths, commands, database topology, financial semantics,
and other local assumptions. Global roles must obtain project paths, base branch, validation commands,
and domain invariants from the task brief and project-local instructions.

Update global routing so `deps-researcher` is required before adopting or replacing an npm package
and before a major upgrade; patch/minor upgrades route to it only for compatibility or security
uncertainty. The researcher is read-only and returns a ranked, evidence-backed recommendation plus an
install command; it never installs or edits.

Preserve `model: sonnet` and `codex_model: gpt-5.6-sol` for engineers/researcher; preserve
`model: opus` and `codex_model: gpt-5.6-sol` for reviewers. Use `gh-axi`, not raw `gh`.

**Out of scope:** all files under `projects/yavo/`; `deputy`, `mechanical-reviewer`, React Native,
non-npm ecosystems, application code, deployment, secrets, and user-owned `tasks/plan.md` and
`tasks/todo.md`.

## Brief — deputy

Read `RULES.md`, `agents/orchestrator.md`, the five source roles under `projects/yavo/agents/`, and
the existing global NestJS roles. Implement the scope above as reusable global Jarvis roles. Do not
copy Yavo-specific facts into shared roles. Keep each role operational: explicit inputs, authority,
workflow, verification, report contract, and stop conditions. Add or extend fixture-safe role tests
where useful so frontmatter, global fallback, model fields, read-only researcher tools, routing
language, and absence of Yavo-specific strings are mechanically checked.

Use test-first changes for executable behavior. Do not edit anything under `projects/yavo/`.
Commit, push, open a PR to `main`, write `reports/260902-1411-001-deputy.md`, and update this
card and `plan/INDEX.md` at the implementation checkpoint.

## Done means

- `bash tests/role-resolution.test.sh` passes.
- `bash scripts/plan-check.sh` passes.
- `bash scripts/owns-check.sh` passes.
- All five global roles exist with valid frontmatter and the chosen model tiers.
- No global role contains Yavo-specific repository, path, database, or domain assumptions.
- npm researcher routing and read-only authority are explicit in both central rule surfaces.
- PR is open against `main` and the engineer report is committed.

## Decisions still open

None. Scope, adaptation boundary, researcher authority/routing, and model tiers were confirmed by the
user through the `grill-me` interview.

## Rounds

Append a `## Review round N` section per round: verdict, findings, fixes, and deliberately deferred
items with reasons. The review ceiling is two rounds.

## Implementation checkpoint (deputy) — 2026-09-02

All five global roles written (two existing NestJS roles rewritten from verbatim Yavo copies to
templated global roles; three new: nextjs-engineer, nextjs-reviewer, deps-researcher). RULES.md and
agents/orchestrator.md updated with deps-researcher routing. tests/role-resolution.test.sh extended.
`bash tests/role-resolution.test.sh`, `bash scripts/plan-check.sh`, `bash scripts/owns-check.sh` all
pass. Full account: `reports/260902-1411-001-deputy.md`. PR #4 open against `main`, awaiting review.

## Reconciliation checkpoint (deputy) - 2026-09-03

Merged `origin/main` (which now carries merged PR #5, `b7f3706`) into `harness/260902-1411-001` as
`5a71d25`. Merge, not rebase: the branch is already pushed under an open PR and force-pushes are not
pre-authorized.

- `RULES.md` and `agents/orchestrator.md` auto-merged with no conflict - both concerns are present
  and neither was dropped: the `deps-researcher` routing bullets (RULES.md:33-37,
  orchestrator.md:131-134) and main's anti-proxy / capability-preflight rules (RULES.md:51-58,
  orchestrator.md:99-102).
- `plan/INDEX.md` was the only conflict, and only because main widened the table columns to fit the
  new `260902-1545-001` row. Resolved to main's version, which is a strict superset - the
  `260902-1411-001` row is byte-identical in both.
- Everything else the branch had added (OVERVIEW entry, this card, the two 1204 artifacts, the
  deputy report) is already byte-identical on `main`, so it left the PR diff entirely.

PR #4 now diffs against `main` as exactly the eight files this card claims under `Owns:`
(929 insertions, 167 deletions). Full test suite: 24/24 pass, including main's four new
capability/MCP suites and `tests/anti-proxy-rule.test.sh` against the merged rule files.
`plan-check.sh` and `owns-check.sh` pass. Ready for round 1 logic-tier review.

## Review round 1 - 2026-09-03 (reviewer, logic tier)

**Verdict: REQUEST_CHANGES.** Reviewed `b7f3706..e24cef9` (the brief named tip `5a71d25`; the pushed
PR tip is `e24cef9`, two doc-only plan commits later). Full account:
`reports/260902-1411-001-reviewer.md`.

Verified independently: full suite 24/24, `plan-check.sh`, `owns-check.sh`, `review-rounds.sh` all
pass; the deputy's "eight files, 929/167 at 5a71d25" claim is exact; no Yavo regression, since
`projects/yavo/agents/` carries project-local overrides for all five roles and `role_path()` prefers
them. Three of the new test assertions were mutation-verified and do catch real breakage (M1-M3).

**Blockers**

1. `tools:` frontmatter is inert. `engine_start()` (`scripts/agent-engine-lib.sh:197-215`) reads only
   `model`/`effort`/`codex_model`/`capabilities` and launches with `--permission-mode
   bypassPermissions` (line 210) - no tool restriction. So `deps-researcher`'s read-only authority,
   the property the user explicitly chose, is prose only, while
   `tests/role-resolution.test.sh:133-139` certifies it as a guarantee. `Bash` in the same `tools:`
   line would defeat it even if the field were honored. Either enforce the field in `engine_start()`
   or drop it and stop testing it as a restriction.
2. `agents/nestjs-reviewer.md:41-42` instructs a read-only reviewer to run migrations, contradicting
   `:53` ("never run a migration") in the same file. Copy-paste leak from `nestjs-engineer.md:33-35`,
   where it is correct. Delete the sentence.

**Should fix**

3. Both new reviewers emit `Verdict: pass | changes required` (`nestjs-reviewer.md:170`,
   `nextjs-reviewer.md:173`) instead of `APPROVE` / `REQUEST_CHANGES` - the token `RULES.md:116`,
   `RULES.md:141` and `orchestrator.md:157,188` gate "done" and merge on, and the vocabulary every
   other reviewer role in the harness uses. No script parses verdicts (verified), so the break lands
   on the lead.
4. Both new reviewers drop the `reports/<task>-<agent>.md` file and the <=15-line return that
   `RULES.md:190-191` mandates and `reviewer.md:57` states. Round-2 briefs then have no findings path
   to cite.
5. Both engineer roles say "get a recommendation from `deps-researcher` first"
   (`nestjs-engineer.md:89-90`, `nextjs-engineer.md:82-83`) - a dispatch an engineer cannot perform.
   Should be "stop and report that the task needs one; the lead dispatches it."
6. The `middleware.ts` constraint (`nextjs-engineer.md:62-63`, `nextjs-reviewer.md:77`) keys the
   highest-blast-radius guard on a filename Next.js 16 renamed to `proxy.ts`. A `proxy.ts` change
   escapes both the approval constraint and the reviewer's first-priority check.
7. `next lint` (`nextjs-engineer.md:198`) was removed in Next 16, and `next build` no longer lints -
   so the verify order silently loses lint coverage on a current project.
8. The new "global fallback" assertion (`tests/role-resolution.test.sh:156-157`) greps a `die`
   message, not the resolver (`role_path()` lives in `herdr-runtime-lib.sh:123-128`). Measured: M4
   broke the real resolution and was caught by the pre-existing fixture test, not by this assertion;
   M5 changed only the error-message wording and failed the suite. Zero coverage, one false-failure
   mode. Delete it.

**Consider:** 9. `.claude/stack.yml` survives at `deps-researcher.md:25` as a named project-local
path in a global role, and the deputy report overstates it as "dropped"; the Yavo-string test is
name-based and cannot see it. 10. `deps-researcher`'s verdict has no durable home, though
`nestjs-engineer.md:302-304` requires it "on record" - the lead should paste it into the card.

**Not checked:** adaptation fidelity line-by-line against `projects/yavo/agents/` (absent from this
worktree), the roles in a live dispatch, the codex engine, and CI (this repo has no `.github/` and
PR #4 has no checks configured).

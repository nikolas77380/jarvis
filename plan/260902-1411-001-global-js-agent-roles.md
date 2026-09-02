# 260902-1411-001 — global-js-agent-roles

**Status:** open · **Owner:** general-purpose · **Blocks:** — · **Depends on:** —
**Validation:** strict
**Engine:** claude
PR: none yet
**Next:** dispatch `general-purpose` with `scripts/agent-spawn.sh 260902-1411-001`

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

## Brief — general-purpose

Read `RULES.md`, `agents/orchestrator.md`, the five source roles under `projects/yavo/agents/`, and
the existing global NestJS roles. Implement the scope above as reusable global Jarvis roles. Do not
copy Yavo-specific facts into shared roles. Keep each role operational: explicit inputs, authority,
workflow, verification, report contract, and stop conditions. Add or extend fixture-safe role tests
where useful so frontmatter, global fallback, model fields, read-only researcher tools, routing
language, and absence of Yavo-specific strings are mechanically checked.

Use test-first changes for executable behavior. Do not edit anything under `projects/yavo/`.
Commit, push, open a PR to `main`, write `reports/260902-1411-001-general-purpose.md`, and update this
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

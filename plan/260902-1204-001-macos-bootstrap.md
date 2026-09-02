# 260902-1204-001 — macos-bootstrap

**Status:** in-review · **Owner:** shell-engineer · **Blocks:** — · **Depends on:** 260831-2017-001
**Validation:** strict
**Engine:** claude
PR: #3
**Next:** run `scripts/review-rounds.sh 260902-1204-001`, then dispatch round 1 of 2 against the
full diff at `03dfb01` (PR #3) to the logic-tier reviewer — the diff touches `bin/jarvis`'s root
resolution, a shared entry point, alongside the new `bootstrap.sh`.

<!--
HOW TO USE THIS FILE
Install it as `projects/<project>/plan/TEMPLATE.md` — INSIDE that project's own checkout — copy it to
`plan/Tnn-<slug>.md` per task, and delete this comment. Add the task's line to `plan/INDEX.md` in the
same change; cross-task ordering lives THERE, never only here.

The harness root itself is the one reserved exception: project id `jarvis` resolves to the harness
root checkout rather than `projects/jarvis` (there is no `projects/jarvis` — that name is reserved
and refused), so a root `plan/` — like this one — is legitimate and is the harness's own plan. Every
other project's plan/ still lives INSIDE that project's own checkout, never at the harness root.
Herdr creates each task's isolated worktree from that resolved checkout, and that worktree only ever
contains what is committed to that project's own repo — so the card, the claim lock under
`plan/.claims/`, and the review-rounds ledger all have to live inside the project's checkout to stay
visible across its worktrees. `task_card` in `scripts/herdr-runtime-lib.sh` finds a card by scanning
every `projects/*/plan/` plus the root `plan/`, and derives the project from WHICH one it found the
card in via `card_project` — there is no `**Project:**` header field to keep in sync by hand.

The header fields are parsed, not decoration:
  **Status:**  handoff.sh prints it back at you  (open · in-progress · in-review · blocked ·
               needs-decision · done)
  PR:          review-rounds.sh reads it with ^\**PR\**:?\s*#(\d+) — it MUST be on its own line and
               it MUST be the digits, `PR: #18`. A PR mentioned in prose is not declared, and a
               loose match once attributed one PR's review rounds to three different tasks.
  **Next:**    the literal next dispatch or command. A resuming session must be able to EXECUTE it
               without deriving it: "dispatch api-engineer with the brief under ## Brief" or "run
               scripts/review-rounds.sh T08, then dispatch round 2 against 3f91c02..HEAD with the
               two findings under ## Review round 1". "Continue T08" is not a next action.

Rewrite **Next:** every time an agent reports back, BEFORE dispatching the next one, and run
`scripts/checkpoint.sh <task>` — it fails while this line is missing or still says the placeholder
above. That write is what makes an interrupted session or a dead run cost one agent run instead of a
whole session.
-->

## What and why

Add a single macOS onboarding command, `./bootstrap.sh`, for a freshly cloned Jarvis repository. It
installs missing runtime dependencies, exposes the global `jarvis` command, verifies the setup, and
prints the explicit Claude authentication/start commands. This removes the current multi-step manual
setup and makes first-run behavior repeatable.

User decisions from the `grill-me` interview: macOS only; Homebrew is a prerequisite and is never
installed automatically; existing tool versions are not upgraded; missing Herdr uses
`curl -fsSL https://herdr.dev/install.sh | sh`; missing Claude Code uses the official native stable
installer; the script creates `~/.local/bin/jarvis`; authentication is left interactive after setup.

## Scope

**Owns:** `bootstrap.sh`, `tests/bootstrap*.test.sh`, `README.md`, `docs/herdr-runtime.md`,
`bin/jarvis` (root-resolution fix only — see note below; approved by user 2026-09-02)

**Out of scope:** runtime behavior under `scripts/`, reviewer/QA flow, Linux/Windows support,
automatic upgrades, Homebrew installation, Claude credentials/tokens, and user task files.

**Discovered during implementation:** `bin/jarvis` computed its root via a plain
`dirname "${BASH_SOURCE[0]}"`, which bash does not resolve through a symlink — so the literal
`~/.local/bin/jarvis` symlink this task creates would, once invoked via `PATH`, compute the wrong
root and fail to source `scripts/`. This is why the existing `bin/jarvis install-alias` command uses
a shell alias with a baked-in path instead of a symlink. Confirmed with the user 2026-09-02: fix
`bin/jarvis`'s root resolution (a small symlink-following loop) rather than change the symlink
approach. This is the only change to `bin/jarvis`; its behavior is otherwise unchanged and covered
by the existing `tests/jarvis-cli.test.sh` (still green) plus this task's own symlink-invocation
coverage in `tests/bootstrap.test.sh` and `tests/bootstrap-interactive.test.sh`.

## Brief — shell-engineer

Implement executable `bootstrap.sh` for a fresh macOS clone, using TDD and fixture-isolated HOME/PATH
so tests never modify the real machine. Read `RULES.md` fully. The script must:

1. Require Darwin and fail clearly elsewhere. Require `brew`; if absent, stop and print the official
   Homebrew installation URL/command without executing it.
2. Install only missing `git` and `jq` with Homebrew. Never upgrade an existing command.
3. Install missing Herdr with the user-approved official command
   `curl -fsSL https://herdr.dev/install.sh | sh`. Install missing Claude Code with the official
   stable native installer `curl -fsSL https://claude.ai/install.sh | bash -s stable`. Do not run
   either installer when its command already works.
4. Create `~/.local/bin/jarvis` as a symlink to this clone's absolute `bin/jarvis`. Ensure
   `~/.local/bin` is exported from `~/.zprofile` exactly once. If the destination is an unexpected
   file/symlink, ask before replacing in an interactive terminal and fail without mutation when
   non-interactive.
5. Be safely idempotent. Stage risky writes so a failed dependency install does not publish a broken
   `jarvis` command. Quote all paths, including clone paths containing spaces.
6. Verify `git`, `jq`, `herdr`, `claude`, the symlink target, PATH configuration, and read-only
   `bin/jarvis status`. Do not start Jarvis and do not perform login. Finish with exactly useful next
   actions: `Authenticate: claude` and `Start Jarvis: jarvis claude`.

Tests must fake `uname`, `brew`, `curl`, installers, commands, HOME, and PATH. Cover fresh install,
fully installed rerun, missing Homebrew, non-macOS, dependency failure, path with spaces, profile
deduplication, expected symlink repair, unexpected destination refusal, and interactive confirmation.
Update README setup instructions and cite the official installer URLs. Do not touch `tasks/plan.md`
or `tasks/todo.md`. Commit, push, open a PR to `main`, and write
`reports/260902-1204-001-shell-engineer.md`.

## Done means

- `bash tests/bootstrap.test.sh` passes.
- All `tests/*.test.sh` pass.
- `scripts/plan-check.sh` and `scripts/owns-check.sh` pass.
- `shellcheck bootstrap.sh` passes when ShellCheck is available; absence is reported as unverified.
- PR is open against `main`, with the engineer report committed.

## Decisions still open

None. All installer authority, channel, upgrade, shell-profile, conflict, authentication, and final
command choices were confirmed by the user.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

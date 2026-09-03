# 260902-1204-001 — macos-bootstrap

**Status:** in-progress · **Owner:** shell-engineer · **Blocks:** — · **Depends on:** 260831-2017-001
**Validation:** strict
**Engine:** claude
PR: #3
**Next:** hand PR #3 back to the engineer for the round-1 fix delta with
`scripts/agent-review.sh 260902-1204-001 shell-engineer --brief-file plan/260902-1204-001-macos-bootstrap.md --engine claude`,
briefing it on findings 1-3 under `## Review round 1` (findings 4-6 are its call, each either fixed
or declined on the card with a reason). Round 1 of 2 is spent: the next reviewer dispatch is the
LAST one, reviews only `c29e209..<fix tip>`, and re-runs every check in full.

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

**Owns:** `bootstrap.sh`, `tests/bootstrap*.test.sh`, `README.md`, `docs/herdr-runtime.md`

**Out of scope:** runtime behavior under `scripts/`, reviewer/QA flow, Linux/Windows support,
automatic upgrades, Homebrew installation, Claude credentials/tokens, and user task files.

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

## Implementation checkpoint

PR #3 is open at implementation tip `03dfb01`; the branch card/report commit is `c29e209`.
The engineer reports 21/21 shell tests passing, `shellcheck bootstrap.sh` clean, and plan/ownership
checks green. The implementation also fixes `bin/jarvis` root resolution through the installed
symlink, which is why the full diff requires the logic-tier reviewer.

## Decisions still open

None. All installer authority, channel, upgrade, shell-profile, conflict, authentication, and final
command choices were confirmed by the user.

## Rounds

Append a `## Review round N` section per round: verdict, what was found, what was fixed, and anything
deliberately left alone with the reason. `scripts/review-rounds.sh` compares these headings against
what actually ran in the transcripts, and the ceiling is two.

## Review round 1

**Verdict:** REQUEST_CHANGES · **Reviewer:** shell-reviewer (logic tier) · **Reviewed:**
`main...c29e209`, implementation tip `03dfb01` · **Full report:**
`reports/260902-1204-001-shell-reviewer.md`

Ran in the lead session under the `shell-reviewer` role rather than a Herdr reviewer tab, so
`scripts/review-rounds.sh` sees `ran 0` against `recorded 1`. This heading is the round of record.

**Checks re-run by the reviewer** (not taken from the engineer summary): 21/21 `tests/*.test.sh`
PASS individually · `shellcheck bootstrap.sh` clean · `shellcheck bin/jarvis` clean within the
diffed hunk (SC1091 x3 and SC2034 are pre-existing, outside the diff) · `scripts/plan-check.sh` ok ·
`scripts/owns-check.sh` ok (1 active card, 4 claims, no overlap; `bin/jarvis` is properly declared
under `Owns:` with the recorded user approval).

### Blockers — must close to pass round 2

1. **The fresh-macOS path aborts after a successful installer run.** `bootstrap.sh:60-78`
   (`ensure_herdr`, `ensure_claude`) confirm the install with `command -v` against the current
   process PATH, but `$HOME/.local/bin` is never added to it: `ensure_path_export`
   (`bootstrap.sh:80-88`) only appends to `~/.zprofile`, and `main` calls it at line 155, after both
   installers. Both official installers place their binary in `~/.local/bin` — measured on the
   review host: `command -v claude` → `/Users/nikolaykipniak/.local/bin/claude`, `command -v herdr` →
   `/Users/nikolaykipniak/.local/bin/herdr`. That is the same directory `verify`
   (`bootstrap.sh:137-142`) already assumes may be absent from PATH. Reproduced with a fixture whose
   fake installers write into `$HOME/.local/bin` while PATH excludes it: the run dies with
   `error: herdr installation did not put herdr on PATH` while `$HOME/.local/bin/herdr` exists and is
   executable; `ensure_claude` fails identically once herdr is out of the way. So the primary
   scenario the script exists for fails closed with a misleading message. The suite cannot catch it
   because `fake_curl` installs into `$BOOTSTRAP_TEST_BIN` (`tests/bootstrap.test.sh:88`, `:95`) and
   `run_bootstrap` sets `PATH="$dir/bin"` to that same directory (`tests/bootstrap.test.sh:113`) —
   the fixture installer always installs onto PATH, which no real installer guarantees.
   *Fix:* export `PATH="$HOME/.local/bin:$PATH"` idempotently inside `bootstrap.sh` before the
   installer steps, plus a case whose fake installer targets `$HOME/.local/bin` with PATH excluding
   it.

2. **`mv` onto a directory destination moves the link inside it instead of replacing it.**
   `bootstrap.sh:119-121` stages `ln -s` to a temp name and then `mv "$tmp_link" "$JARVIS_LINK"`.
   BSD `mv` resolves a directory destination, and follows a symlink to one, and moves the source
   *into* it. Measured on the review host: `mv tmp_link dest_dir` left `dest_dir` intact with the
   link at `dest_dir/tmp_link`; with `jarvis -> realdir` staged, `mv tmp2 jarvis` left `jarvis`
   pointing at `realdir` and dropped the link at `realdir/tmp2`. Two reachable paths:
   `bootstrap.sh:116-118`, where the destination is a directory — `confirm_replace` asks, the user
   agrees, nothing is replaced, a stray `.jarvis.bootstrap.<pid>` is left inside it, and `verify`
   then dies at `bootstrap.sh:133`, so a granted confirmation yields both a failure and litter; and
   `bootstrap.sh:109-115`, where a stale symlink pointing at a *directory* is "repaired" with no
   prompt at all, so the repair silently does nothing and litters the old target. Neither is
   covered: test 8 uses a symlink to a non-existent file (`tests/bootstrap.test.sh:263`), and test 9
   plus both interactive cases use a regular file.
   *Fix:* unlink the destination explicitly before the atomic rename (BSD `mv` has no `-T`), or use
   `ln -sfn`, and reject a directory destination outright in `ensure_symlink` rather than routing it
   through `confirm_replace` as if replacement would work. Add both directory cases.

3. **`ZDOTDIR` is ignored, so the PATH export can land in a file zsh never reads.**
   `bootstrap.sh:81` uses `$HOME/.zprofile` unconditionally. With `ZDOTDIR` set, zsh reads
   `$ZDOTDIR/.zprofile`, so the export is written where nothing sources it: `jarvis` silently never
   reaches PATH while bootstrap reports success and `verify` prints the reassuring "added to
   ~/.zprofile" line. This repo already has the convention — `bin/jarvis install-alias` uses
   `${ZDOTDIR:-$HOME}/.zshrc` (`bin/jarvis:108`). Non-blocking on its own, but it lives in the same
   function as finding 1, so it closes in the same round.
   *Fix:* `${ZDOTDIR:-$HOME}/.zprofile`, with the resolved path reflected at `bootstrap.sh:83`,
   `:87`, `:141`.

### Engineer's call — fix or decline with a reason on this card

4. `~/.zprofile` is mutated before `ensure_symlink` can refuse (`main` line 155 before 156), so a
   declined confirmation at `bootstrap.sh:117` fails with the profile already edited. Test 9 asserts
   the destination file was not mutated (`tests/bootstrap.test.sh:287-288`) but says nothing about
   the profile, so the behaviour is unspecified rather than chosen.
5. The temp symlink leaks on `mv` failure — `bootstrap.sh:119-121` has no trap or cleanup, so a
   failure under `set -e` leaves `~/.local/bin/.jarvis.bootstrap.<pid>` in a directory about to be
   put on the user's PATH.
6. The symlink-resolution loop has no iteration cap (`bootstrap.sh:9-16`, `bin/jarvis:4-11`), so a
   symlink cycle spins forever instead of failing. `bin/jarvis` is the shared entry point every
   command goes through, which makes the counter worth having.

### Confirmed sound — do not re-litigate in round 2

The `bin/jarvis:3-12` root-resolution fix is the correct idiom, is genuinely required by the symlink
this task installs, and is exercised end to end: `verify` invokes `"$JARVIS_LINK" status`
(`bootstrap.sh:143`), so the fresh and path-with-spaces cases run `bin/jarvis` *through* the
installed symlink and would turn red if the loop were removed. Fixture isolation is real (per-case
HOME, curated PATH dir, own clone copy plus the three sourced libs, `never_call` shims that fail the
test on an unexpected `brew`/`curl`). Idempotence is asserted rather than claimed (case 2 fails on
any `brew`/`curl` invocation; case 7 runs twice and counts the profile line). Homebrew is printed
and never executed, with case 3 asserting no symlink and no `.zprofile`. The `pwd -P` fixture
comment and the `docs/herdr-runtime.md` rationale for the resolution loop both earn their place.

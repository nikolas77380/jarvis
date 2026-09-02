#!/usr/bin/env bash
# bootstrap.sh runs against a fully isolated fixture per case: its own HOME, its own curated bin
# dir standing in for PATH (so the real host's git/jq/herdr/claude/brew/curl/uname are never
# reachable — only what a case explicitly stages), and its own copy of the clone (bootstrap.sh,
# bin/jarvis, and the libs bin/jarvis sources). Nothing here ever touches the real machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Physically resolved (`pwd -P`): bootstrap.sh itself resolves its own location through `cd -P`, and
# on macOS `mktemp -d` returns a path under /var/folders/... whose physical form is
# /private/var/folders/... — comparing against the raw mktemp output would spuriously mismatch.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

REAL_TOOLS="bash sh dirname mkdir ln mv grep cat readlink rm chmod cp sed tail"

# new_case <name> [clone-subdir-name] -> prints the case directory
new_case() {
  local name=$1 clone_name=${2:-clone}
  local dir="$TMP/$name"
  mkdir -p "$dir/$clone_name/bin" "$dir/$clone_name/scripts" "$dir/home" "$dir/bin"
  cp "$ROOT/bootstrap.sh" "$dir/$clone_name/bootstrap.sh"
  cp "$ROOT/bin/jarvis" "$dir/$clone_name/bin/jarvis"
  cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" \
    "$ROOT/scripts/jarvis-runtime-lib.sh" "$dir/$clone_name/scripts/"
  chmod +x "$dir/$clone_name/bootstrap.sh" "$dir/$clone_name/bin/jarvis"
  local t real
  for t in $REAL_TOOLS; do
    real=$(command -v "$t") || continue
    ln -s "$real" "$dir/bin/$t"
  done
  printf '%s\n' "$dir"
}

fake_uname() {
  local dir=$1 os=$2
  cat > "$dir/bin/uname" <<EOF
#!/bin/sh
echo $os
EOF
  chmod +x "$dir/bin/uname"
}

# A working fake Homebrew: logs every invocation, and on "install <pkg>" drops a fake <pkg>
# executable into the case's bin dir (unless $BREW_FAIL names that exact package).
fake_brew() {
  local dir=$1
  cat > "$dir/bin/brew" <<'EOF'
#!/bin/sh
: "${BREW_LOG:?}"; : "${BOOTSTRAP_TEST_BIN:?}"
echo "brew $*" >> "$BREW_LOG"
if [ "$1" = install ]; then
  shift
  for pkg in "$@"; do
    if [ "$pkg" = "${BREW_FAIL:-}" ]; then
      echo "brew: failed to install $pkg" >&2
      exit 1
    fi
    printf '#!/bin/sh\necho "%s (fake, installed by brew)"\n' "$pkg" > "$BOOTSTRAP_TEST_BIN/$pkg"
    chmod +x "$BOOTSTRAP_TEST_BIN/$pkg"
  done
fi
EOF
  chmod +x "$dir/bin/brew"
}

# A working fake curl that understands exactly the two installer URLs bootstrap.sh fetches. It
# never installs anything itself — like the real command, it prints a script to stdout that the
# caller pipes into sh/bash, which is what actually creates the fake herdr/claude executables (or,
# under *_FAIL, fails without creating anything).
fake_curl() {
  local dir=$1
  cat > "$dir/bin/curl" <<'EOF'
#!/bin/sh
: "${BOOTSTRAP_TEST_BIN:?}"
URL=""
for a in "$@"; do
  case "$a" in http*) URL=$a ;; esac
done
echo "curl $URL" >> "${CURL_LOG:?}"
case "$URL" in
  *herdr.dev*)
    if [ -n "${HERDR_FAIL:-}" ]; then
      echo 'echo herdr install failed >&2; exit 1'
    else
      echo "printf '#!/bin/sh\necho herdr-fake\n' > \"$BOOTSTRAP_TEST_BIN/herdr\"; chmod +x \"$BOOTSTRAP_TEST_BIN/herdr\""
    fi
    ;;
  *claude.ai*)
    if [ -n "${CLAUDE_FAIL:-}" ]; then
      echo 'echo claude install failed >&2; exit 1'
    else
      echo "printf '#!/bin/sh\necho claude-fake\n' > \"$BOOTSTRAP_TEST_BIN/claude\"; chmod +x \"$BOOTSTRAP_TEST_BIN/claude\""
    fi
    ;;
  *) echo 'exit 1' ;;
esac
EOF
  chmod +x "$dir/bin/curl"
}

# Like fake_curl, but mimics what the REAL herdr/claude installers actually do: write their binary
# into $HOME/.local/bin, not onto whatever directory the fixture happens to put on PATH. Regression
# fixture for round 1 finding 1.
fake_curl_to_home() {
  local dir=$1
  cat > "$dir/bin/curl" <<'EOF'
#!/bin/sh
: "${CURL_LOG:?}"
URL=""
for a in "$@"; do
  case "$a" in http*) URL=$a ;; esac
done
echo "curl $URL" >> "$CURL_LOG"
case "$URL" in
  *herdr.dev*) echo "mkdir -p \"$HOME/.local/bin\"; printf '#!/bin/sh\necho herdr-fake\n' > \"$HOME/.local/bin/herdr\"; chmod +x \"$HOME/.local/bin/herdr\"" ;;
  *claude.ai*) echo "mkdir -p \"$HOME/.local/bin\"; printf '#!/bin/sh\necho claude-fake\n' > \"$HOME/.local/bin/claude\"; chmod +x \"$HOME/.local/bin/claude\"" ;;
  *) echo 'exit 1' ;;
esac
EOF
  chmod +x "$dir/bin/curl"
}

# A trivial always-present tool, for pre-staging "already installed" fixtures.
stage_present() {
  local dir=$1 name=$2
  printf '#!/bin/sh\necho "%s (pre-staged)"\n' "$name" > "$dir/bin/$name"
  chmod +x "$dir/bin/$name"
}

run_bootstrap() {
  local dir=$1 clone_name=${2:-clone} status=0
  HOME="$dir/home" PATH="$dir/bin" BOOTSTRAP_TEST_BIN="$dir/bin" \
    BREW_LOG="${BREW_LOG:-$dir/brew.log}" CURL_LOG="${CURL_LOG:-$dir/curl.log}" \
    BREW_FAIL="${BREW_FAIL:-}" HERDR_FAIL="${HERDR_FAIL:-}" CLAUDE_FAIL="${CLAUDE_FAIL:-}" \
    bash "$dir/$clone_name/bootstrap.sh" </dev/null >"$dir/out.log" 2>&1 || status=$?
  return "$status"
}

# =========================================================================
# 1. Fresh install: nothing pre-staged except a working brew/curl/uname.
# =========================================================================
D=$(new_case fresh)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "fresh install exited $STATUS"; }
grep -q '^brew install git$' "$D/brew.log" || fail "fresh install: brew was not asked to install git"
grep -q '^brew install jq$' "$D/brew.log" || fail "fresh install: brew was not asked to install jq"
[ -x "$D/bin/git" ] || fail "fresh install: fake git was not installed"
[ -x "$D/bin/jq" ] || fail "fresh install: fake jq was not installed"
[ -x "$D/bin/herdr" ] || fail "fresh install: herdr was not installed"
[ -x "$D/bin/claude" ] || fail "fresh install: claude was not installed"
LINK="$D/home/.local/bin/jarvis"
[ -L "$LINK" ] || fail "fresh install: $LINK is not a symlink"
[ "$(readlink "$LINK")" = "$D/clone/bin/jarvis" ] || fail "fresh install: symlink target is wrong"
grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$D/home/.zprofile" \
  || fail "fresh install: PATH export missing from ~/.zprofile"
grep -q '^  Authenticate: claude$' "$D/out.log" || fail "fresh install: missing 'Authenticate: claude' next action"
grep -q '^  Start Jarvis: jarvis claude$' "$D/out.log" || fail "fresh install: missing 'Start Jarvis: jarvis claude' next action"
echo "case 1 (fresh install): ok"

# =========================================================================
# 2. Fully installed rerun: everything already present and correct; nothing should be reinstalled
#    or duplicated.
# =========================================================================
D=$(new_case rerun)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
stage_present "$D" git
stage_present "$D" jq
stage_present "$D" herdr
stage_present "$D" claude
mkdir -p "$D/home/.local/bin"
ln -s "$D/clone/bin/jarvis" "$D/home/.local/bin/jarvis"
printf '# existing profile content\n%s\n' 'export PATH="$HOME/.local/bin:$PATH"' > "$D/home/.zprofile"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "rerun exited $STATUS"; }
[ ! -s "$D/brew.log" ] || fail "rerun: brew was invoked when everything was already present: $(cat "$D/brew.log")"
[ ! -s "$D/curl.log" ] || fail "rerun: curl was invoked when everything was already present: $(cat "$D/curl.log")"
[ "$(readlink "$D/home/.local/bin/jarvis")" = "$D/clone/bin/jarvis" ] || fail "rerun: symlink no longer correct"
COUNT=$(grep -c 'export PATH="\$HOME/.local/bin:\$PATH"' "$D/home/.zprofile")
[ "$COUNT" -eq 1 ] || fail "rerun: PATH export duplicated ($COUNT occurrences)"
grep -q '^# existing profile content$' "$D/home/.zprofile" || fail "rerun: unrelated profile content was lost"
echo "case 2 (fully installed rerun): ok"

# =========================================================================
# 3. Missing Homebrew: must stop and print the official install command/URL, without executing it.
# =========================================================================
D=$(new_case no_brew)
fake_uname "$D" Darwin

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -ne 0 ] || fail "missing-brew case unexpectedly succeeded"
grep -qF 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' "$D/out.log" \
  || fail "missing-brew case did not print the official Homebrew install command"
grep -qF 'https://brew.sh' "$D/out.log" || fail "missing-brew case did not print the Homebrew URL"
[ ! -e "$D/home/.local/bin/jarvis" ] || fail "missing-brew case created the jarvis symlink"
[ ! -e "$D/home/.zprofile" ] || fail "missing-brew case touched ~/.zprofile"
echo "case 3 (missing Homebrew): ok"

# =========================================================================
# 4. Non-macOS: must fail clearly and immediately.
# =========================================================================
D=$(new_case non_macos)
fake_uname "$D" Linux
fake_brew "$D"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -ne 0 ] || fail "non-macOS case unexpectedly succeeded"
grep -qi 'macos' "$D/out.log" || fail "non-macOS case did not explain the macOS requirement"
grep -qF 'Linux' "$D/out.log" || fail "non-macOS case did not name the detected OS"
[ ! -s "$D/brew.log" ] || fail "non-macOS case invoked brew"
echo "case 4 (non-macOS): ok"

# =========================================================================
# 5. Dependency install failure: must abort and must not publish a broken jarvis command.
# =========================================================================
D=$(new_case dep_fail)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
stage_present "$D" git
BREW_FAIL=jq
STATUS=0; run_bootstrap "$D" || STATUS=$?
BREW_FAIL=
[ "$STATUS" -ne 0 ] || fail "dependency-failure case unexpectedly succeeded"
grep -qF 'failed to install jq' "$D/out.log" || fail "dependency-failure case did not surface the brew failure"
[ ! -e "$D/home/.local/bin/jarvis" ] || fail "dependency-failure case published a jarvis symlink despite the failed install"
[ ! -e "$D/home/.zprofile" ] || fail "dependency-failure case touched ~/.zprofile despite the failed install"
echo "case 5 (dependency install failure): ok"

# =========================================================================
# 6. Path with spaces: the clone itself lives under a directory containing a space.
# =========================================================================
D=$(new_case "path_spaces" "My Clone")
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"

STATUS=0; run_bootstrap "$D" "My Clone" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "path-with-spaces case exited $STATUS"; }
LINK="$D/home/.local/bin/jarvis"
[ -L "$LINK" ] || fail "path-with-spaces case: symlink was not created"
[ "$(readlink "$LINK")" = "$D/My Clone/bin/jarvis" ] || fail "path-with-spaces case: symlink target mismatch: $(readlink "$LINK")"
echo "case 6 (path with spaces): ok"

# =========================================================================
# 7. Profile deduplication across two consecutive runs.
# =========================================================================
D=$(new_case profile_dedup)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
printf '# unrelated pre-existing line\n' > "$D/home/.zprofile"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "profile-dedup case: first run exited $STATUS"; }
STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "profile-dedup case: second run exited $STATUS"; }
COUNT=$(grep -c 'export PATH="\$HOME/.local/bin:\$PATH"' "$D/home/.zprofile")
[ "$COUNT" -eq 1 ] || fail "profile-dedup case: PATH export appeared $COUNT times after two runs"
grep -q '^# unrelated pre-existing line$' "$D/home/.zprofile" || fail "profile-dedup case: unrelated profile content was lost"
echo "case 7 (profile deduplication): ok"

# =========================================================================
# 8. Expected symlink repair: a stale symlink from a previous clone location is silently repaired,
#    without any confirmation prompt (this case runs fully non-interactively).
# =========================================================================
D=$(new_case symlink_repair)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
stage_present "$D" git
stage_present "$D" jq
stage_present "$D" herdr
stage_present "$D" claude
mkdir -p "$D/home/.local/bin"
ln -s "/some/old/clone/bin/jarvis" "$D/home/.local/bin/jarvis"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "symlink-repair case exited $STATUS"; }
[ "$(readlink "$D/home/.local/bin/jarvis")" = "$D/clone/bin/jarvis" ] || fail "symlink-repair case: stale symlink was not repaired"
echo "case 8 (expected symlink repair): ok"

# =========================================================================
# 9. Unexpected destination refusal: a real file sits where the symlink would go. Non-interactive,
#    so bootstrap.sh must refuse without any mutation.
# =========================================================================
D=$(new_case unexpected_dest)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
stage_present "$D" git
stage_present "$D" jq
stage_present "$D" herdr
stage_present "$D" claude
mkdir -p "$D/home/.local/bin"
printf 'not jarvis\n' > "$D/home/.local/bin/jarvis"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -ne 0 ] || fail "unexpected-destination case unexpectedly succeeded"
[ ! -L "$D/home/.local/bin/jarvis" ] || fail "unexpected-destination case replaced the file with a symlink non-interactively"
[ "$(cat "$D/home/.local/bin/jarvis")" = "not jarvis" ] || fail "unexpected-destination case mutated the existing file"
grep -qi 'confirmation' "$D/out.log" || fail "unexpected-destination case did not explain the refusal"
[ ! -e "$D/home/.zprofile" ] || fail "unexpected-destination case wrote ~/.zprofile despite refusing the symlink (round 1 finding 4)"
echo "case 9 (unexpected destination refusal): ok"

# =========================================================================
# 10. Round 1 finding 1 regression: the real herdr/claude installers place their binary in
#    $HOME/.local/bin, not onto whatever directory happens to already be on PATH. bootstrap.sh must
#    put $HOME/.local/bin on its own PATH before checking the installs, or the fresh-macOS path (the
#    scenario the script exists for) fails closed right after a successful install.
# =========================================================================
D=$(new_case installer_writes_to_home)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl_to_home "$D"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "installer-writes-to-\$HOME case exited $STATUS"; }
[ -x "$D/home/.local/bin/herdr" ] || fail "installer-writes-to-\$HOME case: fake herdr was not installed"
[ -x "$D/home/.local/bin/claude" ] || fail "installer-writes-to-\$HOME case: fake claude was not installed"
grep -q '^  Start Jarvis: jarvis claude$' "$D/out.log" \
  || fail "installer-writes-to-\$HOME case: did not reach the final next-actions banner"
echo "case 10 (installers write to \$HOME/.local/bin, excluded from PATH): ok"

# =========================================================================
# 11. Round 1 finding 2 regression (a): a real DIRECTORY sits at the destination. mv onto a
#    directory follows it and moves the temp symlink INSIDE instead of replacing it, so this must be
#    rejected outright, non-interactively, with no litter left behind.
# =========================================================================
D=$(new_case dest_is_directory)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
stage_present "$D" git
stage_present "$D" jq
stage_present "$D" herdr
stage_present "$D" claude
mkdir -p "$D/home/.local/bin/jarvis"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -ne 0 ] || fail "directory-destination case unexpectedly succeeded"
[ -d "$D/home/.local/bin/jarvis" ] && [ ! -L "$D/home/.local/bin/jarvis" ] \
  || fail "directory-destination case: the directory destination was disturbed"
[ -z "$(ls -A "$D/home/.local/bin/jarvis")" ] \
  || fail "directory-destination case: litter was left inside the directory: $(ls -A "$D/home/.local/bin/jarvis")"
grep -qi 'directory' "$D/out.log" || fail "directory-destination case did not explain the refusal"
echo "case 11 (directory destination refusal): ok"

# =========================================================================
# 12. Round 1 finding 2 regression (b): a stale symlink points at a DIRECTORY (not a file). This
#    must repair silently like any other stale symlink, without moving the temp link inside the old
#    target directory.
# =========================================================================
D=$(new_case symlink_to_directory)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
stage_present "$D" git
stage_present "$D" jq
stage_present "$D" herdr
stage_present "$D" claude
mkdir -p "$D/home/.local/bin" "$D/old_target_dir"
ln -s "$D/old_target_dir" "$D/home/.local/bin/jarvis"

STATUS=0; run_bootstrap "$D" || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "symlink-to-directory case exited $STATUS"; }
[ "$(readlink "$D/home/.local/bin/jarvis")" = "$D/clone/bin/jarvis" ] \
  || fail "symlink-to-directory case: stale symlink to a directory was not repaired"
[ -z "$(ls -A "$D/old_target_dir")" ] \
  || fail "symlink-to-directory case: litter was left in the old target directory: $(ls -A "$D/old_target_dir")"
echo "case 12 (stale symlink to a directory repaired): ok"

# =========================================================================
# 13. Round 1 finding 3 regression: with ZDOTDIR set, zsh reads $ZDOTDIR/.zprofile, not
#    $HOME/.zprofile. The PATH export must land where zsh will actually read it.
# =========================================================================
D=$(new_case zdotdir)
fake_uname "$D" Darwin
fake_brew "$D"
fake_curl "$D"
mkdir -p "$D/home/customzdotdir"

export ZDOTDIR="$D/home/customzdotdir"
STATUS=0; run_bootstrap "$D" || STATUS=$?
unset ZDOTDIR
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "ZDOTDIR case exited $STATUS"; }
grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$D/home/customzdotdir/.zprofile" \
  || fail "ZDOTDIR case: PATH export did not land in \$ZDOTDIR/.zprofile"
[ ! -e "$D/home/.zprofile" ] || fail "ZDOTDIR case: PATH export was written to \$HOME/.zprofile instead of \$ZDOTDIR/.zprofile"
echo "case 13 (ZDOTDIR respected for PATH export): ok"

echo "bootstrap tests: ok"

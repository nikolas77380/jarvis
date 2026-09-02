#!/usr/bin/env bash
# Covers the one bootstrap.sh path that only exists under a real terminal: confirming (or
# declining) replacement of an unexpected file at ~/.local/bin/jarvis. `[ -t 0 ]`/`[ -t 1 ]` cannot
# be faked with a pipe, so this drives bootstrap.sh under an actual pseudo-terminal via Python's
# `pty` module (already a project dependency; see scripts/agent-spend.sh and scripts/context-size.sh
# for other Python usage in this repo) and feeds the confirmation reply through it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

PYTHON3=$(command -v python3) || fail "python3 is required to drive bootstrap.sh under a pty for this test"

new_case() {
  local name=$1
  local dir="$TMP/$name"
  mkdir -p "$dir/clone/bin" "$dir/clone/scripts" "$dir/home" "$dir/bin"
  cp "$ROOT/bootstrap.sh" "$dir/clone/bootstrap.sh"
  cp "$ROOT/bin/jarvis" "$dir/clone/bin/jarvis"
  cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" \
    "$ROOT/scripts/jarvis-runtime-lib.sh" "$dir/clone/scripts/"
  chmod +x "$dir/clone/bootstrap.sh" "$dir/clone/bin/jarvis"
  local t real
  for t in bash sh dirname mkdir ln mv grep cat readlink rm chmod cp sed tail; do
    real=$(command -v "$t") || continue
    ln -s "$real" "$dir/bin/$t"
  done
  printf '%s\n' "$dir"
}

stage_present() {
  local dir=$1 name=$2
  printf '#!/bin/sh\necho "%s (pre-staged)"\n' "$name" > "$dir/bin/$name"
  chmod +x "$dir/bin/$name"
}

fake_uname_darwin() {
  printf '#!/bin/sh\necho Darwin\n' > "$1/bin/uname"
  chmod +x "$1/bin/uname"
}

# brew/curl are staged but must never be invoked in these cases (git/jq/herdr/claude are all
# pre-staged as present) — any call is a bug and exits nonzero, which surfaces as a test failure.
never_call() {
  printf '#!/bin/sh\necho "%s must not be invoked in this case" >&2\nexit 1\n' "$2" > "$1/bin/$2"
  chmod +x "$1/bin/$2"
}

cat > "$TMP/pty_driver.py" <<'PY'
import os, pty, sys

reply = sys.argv[1]
cmd = sys.argv[2:]

pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)

os.write(fd, (reply + "\n").encode())
output = b""
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    output += chunk

_, status = os.waitpid(pid, 0)
code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
sys.stdout.buffer.write(output)
sys.exit(code)
PY

run_bootstrap_pty() {
  local dir=$1 reply=$2 status=0
  HOME="$dir/home" PATH="$dir/bin" BOOTSTRAP_TEST_BIN="$dir/bin" \
    "$PYTHON3" "$TMP/pty_driver.py" "$reply" bash "$dir/clone/bootstrap.sh" \
    >"$dir/out.log" 2>&1 || status=$?
  return "$status"
}

# =========================================================================
# 1. Interactive confirm accepted: replying "y" replaces the unexpected file with the symlink.
# =========================================================================
D=$(new_case confirm_yes)
fake_uname_darwin "$D"
never_call "$D" brew
never_call "$D" curl
stage_present "$D" git
stage_present "$D" jq
stage_present "$D" herdr
stage_present "$D" claude
mkdir -p "$D/home/.local/bin"
printf 'not jarvis\n' > "$D/home/.local/bin/jarvis"

STATUS=0; run_bootstrap_pty "$D" y || STATUS=$?
[ "$STATUS" -eq 0 ] || { cat "$D/out.log" >&2; fail "confirm-yes case exited $STATUS"; }
[ -L "$D/home/.local/bin/jarvis" ] || fail "confirm-yes case: destination was not replaced with a symlink"
[ "$(readlink "$D/home/.local/bin/jarvis")" = "$D/clone/bin/jarvis" ] || fail "confirm-yes case: symlink target is wrong"
echo "case 1 (interactive confirm accepted): ok"

# =========================================================================
# 2. Interactive confirm declined: replying "n" leaves the unexpected file untouched and fails.
# =========================================================================
D=$(new_case confirm_no)
fake_uname_darwin "$D"
never_call "$D" brew
never_call "$D" curl
stage_present "$D" git
stage_present "$D" jq
stage_present "$D" herdr
stage_present "$D" claude
mkdir -p "$D/home/.local/bin"
printf 'not jarvis\n' > "$D/home/.local/bin/jarvis"

STATUS=0; run_bootstrap_pty "$D" n || STATUS=$?
[ "$STATUS" -ne 0 ] || fail "confirm-no case unexpectedly succeeded"
[ ! -L "$D/home/.local/bin/jarvis" ] || fail "confirm-no case: destination was replaced despite declining"
[ "$(cat "$D/home/.local/bin/jarvis")" = "not jarvis" ] || fail "confirm-no case: destination content was mutated"
echo "case 2 (interactive confirm declined): ok"

echo "bootstrap interactive tests: ok"

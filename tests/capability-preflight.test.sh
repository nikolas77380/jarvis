#!/usr/bin/env bash
# Roles declare required LIVE capabilities in their own frontmatter (`capabilities: figma`), never a
# name-to-capability map hard-coded in the runtime. capability_preflight_verdict must be fail-closed:
# exactly one well-formed CAPABILITY_PREFLIGHT_RESULT marker must be present and it must be PASS.
# Harmless output around the marker never affects the verdict; a FAIL marker, a timeout, no marker at
# all, a malformed marker, or two marker lines (duplicate PASS, contradictory PASS+FAIL) all fail.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$FAKEBIN"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/agent-engine-lib.sh" "$REPO/scripts/"

cd "$REPO"

(
  # shellcheck source=/dev/null
  . scripts/herdr-runtime-lib.sh
  # shellcheck source=/dev/null
  . scripts/agent-engine-lib.sh

  # role_capabilities: comma-separated, trimmed, absent field -> nothing.
  printf '%s\n' '---' 'model: sonnet' 'capabilities: figma, github' '---' 'body' > role-multi.md
  RESULT=$(role_capabilities role-multi.md | tr '\n' '|')
  [ "$RESULT" = 'figma|github|' ] || { echo "role_capabilities did not parse comma list: $RESULT" >&2; exit 1; }

  printf '%s\n' '---' 'model: sonnet' '---' 'body' > role-none.md
  RESULT=$(role_capabilities role-none.md)
  [ -z "$RESULT" ] || { echo "role_capabilities should be empty when field absent: $RESULT" >&2; exit 1; }

  # capability_preflight_verdict: fail-closed by construction.
  capability_preflight_verdict $'some tool output\nCAPABILITY_PREFLIGHT_RESULT PASS' \
    || { echo "exact PASS as last non-blank line should pass" >&2; exit 1; }
  capability_preflight_verdict $'some tool output\nCAPABILITY_PREFLIGHT_RESULT PASS\n\n\n' \
    || { echo "trailing blank lines after PASS should still pass" >&2; exit 1; }
  ! capability_preflight_verdict $'some tool output\nCAPABILITY_PREFLIGHT_RESULT FAIL figma' \
    || { echo "FAIL marker must not pass" >&2; exit 1; }
  ! capability_preflight_verdict '' \
    || { echo "empty output (timeout/no reply) must not pass" >&2; exit 1; }
  capability_preflight_verdict $'CAPABILITY_PREFLIGHT_RESULT PASS\nsomething harmless printed after it' \
    || { echo "harmless trailing output after a well-formed PASS marker must still pass" >&2; exit 1; }
  ! capability_preflight_verdict 'garbage with no marker at all' \
    || { echo "no marker at all must not pass" >&2; exit 1; }
  ! capability_preflight_verdict $'CAPABILITY_PREFLIGHT_RESULT PASS\nCAPABILITY_PREFLIGHT_RESULT PASS' \
    || { echo "duplicate PASS markers must not pass" >&2; exit 1; }
  ! capability_preflight_verdict $'CAPABILITY_PREFLIGHT_RESULT PASS\nCAPABILITY_PREFLIGHT_RESULT FAIL figma' \
    || { echo "contradictory PASS and FAIL markers must not pass" >&2; exit 1; }
  ! capability_preflight_verdict 'CAPABILITY_PREFLIGHT_RESULT PASS extra text on the marker line' \
    || { echo "a malformed marker line must not pass" >&2; exit 1; }
)

echo 'capability preflight unit tests: ok'

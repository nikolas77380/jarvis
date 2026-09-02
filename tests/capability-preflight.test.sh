#!/usr/bin/env bash
# Roles declare required LIVE capabilities in their own frontmatter (`capabilities: figma`), never a
# name-to-capability map hard-coded in the runtime. capability_preflight_verdict must be fail-closed:
# only the exact PASS marker as the last non-blank line counts as a pass; everything else — a FAIL
# marker, a timeout, stray output, silence — is a failure.
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
  ! capability_preflight_verdict $'CAPABILITY_PREFLIGHT_RESULT PASS\nsomething printed after it' \
    || { echo "PASS not on the LAST line must not pass" >&2; exit 1; }
  ! capability_preflight_verdict 'garbage with no marker at all' \
    || { echo "no marker at all must not pass" >&2; exit 1; }
)

echo 'capability preflight unit tests: ok'

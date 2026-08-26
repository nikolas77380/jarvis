#!/usr/bin/env bash
# Behavior tests for the typed-crewmate role layer (Jarvis extension):
# bin/dj-role-lib.sh, the --role flag on bin/dj-brief.sh, and bin/dj-role.sh.
# The spawn-side agreement check shares dj_role_from_brief/dj_role_valid with
# the brief side, so the contract-line round-trip covered here is the same
# parse the spawn refusal path consumes.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(dj_test_tmproot dj-role-brief)
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/data"

# --- library invariants -----------------------------------------------------

test_lib_registry() {
  # shellcheck source=bin/dj-role-lib.sh
  . "$ROOT/bin/dj-role-lib.sh"
  for r in be fe rn qa reviewer-be reviewer-fe researcher; do
    dj_role_valid "$r" || fail "dj_role_valid rejects known role '$r'"
    [ -n "$(dj_role_codename "$r")" ] || fail "dj_role_codename empty for '$r'"
    [ -f "$ROOT/roles/$r.md" ] || fail "roles/$r.md fragment missing"
  done
  dj_role_valid devops && fail "dj_role_valid accepts unknown role 'devops'"
  expect_code 0 0 "registry sane"
  dj_role_scout_only reviewer-be || fail "reviewer-be must be scout-only"
  dj_role_scout_only reviewer-fe || fail "reviewer-fe must be scout-only"
  dj_role_valid reviewer && fail "legacy generic role 'reviewer' must be invalid after the split"
  dj_role_scout_only researcher || fail "researcher must be scout-only"
  dj_role_scout_only be && fail "be must not be scout-only"
  pass "role registry: names, codenames, fragments, scout-only set"
}

# --- brief scaffolding ------------------------------------------------------

test_ship_brief_records_role() {
  local id=role-ship-be out
  DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-brief.sh" "$id" some-proj --mode direct-PR --role be >/dev/null 2>&1 \
    || fail "ship brief with --role be failed to scaffold"
  out="$HOME_DIR/data/$id/brief.md"
  grep -q '^Role contract: role=be codename=MK38-IGOR$' "$out" \
    || fail "ship brief lacks the fixed role contract line"
  grep -q 'server-side code only' "$out" \
    || fail "ship brief lacks the be role fragment body"
  pass "ship brief: --role be records the contract line and appends roles/be.md"
}

test_scout_brief_records_role() {
  local id=role-scout-edith out
  DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-brief.sh" "$id" some-proj --scout --role researcher >/dev/null 2>&1 \
    || fail "scout brief with --role researcher failed to scaffold"
  out="$HOME_DIR/data/$id/brief.md"
  grep -q '^Role contract: role=researcher codename=FRIDAY$' "$out" \
    || fail "scout brief lacks the researcher contract line"
  pass "scout brief: --role researcher records the contract line"
}

test_untyped_brief_has_no_role_line() {
  local id=role-untyped
  DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-brief.sh" "$id" some-proj --mode direct-PR >/dev/null 2>&1 \
    || fail "untyped brief failed to scaffold"
  grep -q '^Role contract:' "$HOME_DIR/data/$id/brief.md" \
    && fail "untyped brief must not carry a role contract line"
  pass "untyped brief: no role contract line"
}

test_knowledge_only_roles_refuse_ship() {
  local r rc
  for r in reviewer-be reviewer-fe researcher; do
    DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-brief.sh" "role-ship-$r" some-proj --mode direct-PR --role "$r" >/dev/null 2>&1; rc=$?
    expect_code 1 "$rc" "ship brief with knowledge-only role '$r' must be refused"
    [ -e "$HOME_DIR/data/role-ship-$r/brief.md" ] \
      && fail "refused scaffold for '$r' still wrote a brief"
  done
  pass "knowledge-only roles: reviewer-be/reviewer-fe/researcher refuse ship scaffolds"
}

test_invalid_and_misplaced_role() {
  local rc
  DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-brief.sh" role-bad some-proj --mode direct-PR --role devops >/dev/null 2>&1; rc=$?
  expect_code 1 "$rc" "unknown role must be refused"
  DJ_HOME="$HOME_DIR" DJ_SECONDMATE_CHARTER=x "$ROOT/bin/dj-brief.sh" role-sm --secondmate some-proj --role be >/dev/null 2>&1; rc=$?
  expect_code 1 "$rc" "--role on a secondmate charter must be refused"
  pass "refusals: unknown role and --role on --secondmate"
}

# --- dj-role.sh query -------------------------------------------------------

test_role_query() {
  local out rc
  out=$(DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-role.sh" role-ship-be); rc=$?
  expect_code 0 "$rc" "dj-role.sh on a typed task exits 0"
  [ "$out" = "role=be codename=MK38-IGOR" ] || fail "dj-role.sh printed '$out'"
  DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-role.sh" role-untyped >/dev/null 2>&1; rc=$?
  expect_code 3 "$rc" "dj-role.sh on an untyped task exits 3 silently"
  DJ_HOME="$HOME_DIR" "$ROOT/bin/dj-role.sh" role-missing >/dev/null 2>&1; rc=$?
  expect_code 1 "$rc" "dj-role.sh on a missing brief exits 1"
  pass "dj-role.sh: typed/untyped/missing exit contract"
}

test_lib_registry
test_ship_brief_records_role
test_scout_brief_records_role
test_untyped_brief_has_no_role_line
test_knowledge_only_roles_refuse_ship
test_invalid_and_misplaced_role
test_role_query

echo "all dj-role-brief tests passed"

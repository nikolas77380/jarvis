#!/usr/bin/env bash
# Role registry for typed crewmates (Jarvis extension over the upstream harness).
#
# A role is an intake judgment, never a mandatory axis: an untyped task stays
# legal everywhere. When a role IS chosen, this library is the single owner of
# the allowed names, their Stark-robot codenames, and the shape constraint
# (reviewer and researcher are knowledge-only, so they scaffold and spawn as
# scouts, never ships). bin/dj-brief.sh appends the role's standing rules from
# roles/<role>.md and records the fixed machine-readable
# "Role contract: role=<role> codename=<name>" line; bin/dj-spawn.sh refuses a
# brief/spawn role drift, mirroring the delivery-mode contract.
#
# Sourced by dj-brief.sh, dj-spawn.sh, and dj-role.sh; safe under set -eu.

dj_role_valid() {
  case "${1:-}" in
    be|fe|qa|reviewer|researcher) return 0 ;;
    *) return 1 ;;
  esac
}

dj_role_codename() {
  case "${1:-}" in
    be) printf 'DUM-E\n' ;;
    fe) printf 'U\n' ;;
    qa) printf 'BUTTERFINGERS\n' ;;
    reviewer) printf 'FRIDAY\n' ;;
    researcher) printf 'EDITH\n' ;;
    *) return 1 ;;
  esac
}

# Knowledge-only roles: their deliverable is a report, never a merge.
dj_role_scout_only() {
  case "${1:-}" in
    reviewer|researcher) return 0 ;;
    *) return 1 ;;
  esac
}

dj_role_list() {
  printf 'be, fe, qa, reviewer, researcher\n'
}

# dj_role_from_brief <brief-path>: prints the recorded role or nothing.
dj_role_from_brief() {
  sed -n 's/^Role contract: role=\([^ ]*\).*$/\1/p' "$1" | head -n 1
}

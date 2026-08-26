#!/usr/bin/env bash
# Role registry for typed crewmates (Jarvis extension over the upstream harness).
#
# A role is an intake judgment, never a mandatory axis: an untyped task stays
# legal everywhere. When a role IS chosen, this library is the single owner of
# the allowed names, their Stark-armor codenames, and the shape constraint
# (reviewer-be, reviewer-fe, and researcher are knowledge-only, so they scaffold
# and spawn as scouts, never ships). bin/dj-brief.sh appends the role's standing
# rules from roles/<role>.md and records the fixed machine-readable
# "Role contract: role=<role> codename=<name>" line; bin/dj-spawn.sh refuses a
# brief/spawn role drift, mirroring the delivery-mode contract.
#
# Registry:
#   be           MK38-IGOR        Mark 38 "Igor"        backend        ship/scout
#   fe           MK39-STARBOOST   Mark 39 "Starboost"   frontend       ship/scout
#   rn           MK37-HAMMERHEAD  Mark 37 "Hammerhead"  react native   ship/scout
#   qa           MK41-BONES       Mark 41 "Bones"       tests          ship/scout
#   reviewer-be  MK40-SHOTGUN     Mark 40 "Shotgun"     backend review scout only
#   reviewer-fe  MK25-STRIKER     Mark 25 "Striker"     frontend review scout only
#   researcher   FRIDAY           F.R.I.D.A.Y.          investigation  scout only
#
# E.D.I.T.H. is NOT a role: it is the visual review surface (bin/edith, powered
# by the external edith-axi tool) that any crewmate or Jarvis itself raises.
#
# Sourced by dj-brief.sh, dj-spawn.sh, and dj-role.sh; safe under set -eu.

dj_role_valid() {
  case "${1:-}" in
    be|fe|rn|qa|reviewer-be|reviewer-fe|researcher) return 0 ;;
    *) return 1 ;;
  esac
}

dj_role_codename() {
  case "${1:-}" in
    be) printf 'MK38-IGOR\n' ;;
    fe) printf 'MK39-STARBOOST\n' ;;
    rn) printf 'MK37-HAMMERHEAD\n' ;;
    qa) printf 'MK41-BONES\n' ;;
    reviewer-be) printf 'MK40-SHOTGUN\n' ;;
    reviewer-fe) printf 'MK25-STRIKER\n' ;;
    researcher) printf 'FRIDAY\n' ;;
    *) return 1 ;;
  esac
}

# Human-facing armor name for brief prose; the contract line keeps the compact
# codename above.
dj_role_fullname() {
  case "${1:-}" in
    be) printf 'Mark 38 "Igor"\n' ;;
    fe) printf 'Mark 39 "Starboost"\n' ;;
    rn) printf 'Mark 37 "Hammerhead"\n' ;;
    qa) printf 'Mark 41 "Bones"\n' ;;
    reviewer-be) printf 'Mark 40 "Shotgun"\n' ;;
    reviewer-fe) printf 'Mark 25 "Striker"\n' ;;
    researcher) printf 'F.R.I.D.A.Y.\n' ;;
    *) return 1 ;;
  esac
}

# Knowledge-only roles: their deliverable is a report, never a merge.
dj_role_scout_only() {
  case "${1:-}" in
    reviewer-be|reviewer-fe|researcher) return 0 ;;
    *) return 1 ;;
  esac
}

dj_role_list() {
  printf 'be, fe, rn, qa, reviewer-be, reviewer-fe, researcher\n'
}

# dj_role_from_brief <brief-path>: prints the recorded role or nothing.
dj_role_from_brief() {
  sed -n 's/^Role contract: role=\([^ ]*\).*$/\1/p' "$1" | head -n 1
}

#!/usr/bin/env bash
# Read and account for the local startup-memory budget.
# Usage:
#   dj-startup-memory-budget.sh read
#   dj-startup-memory-budget.sh report
#
# `read` prints the one validated effective budget from
# config/startup-memory-budget.  `report` prints the stable local estimate for
# data/captain.md, data/captain-shared.md, and data/learnings.md together.
# Bootstrap owns default materialization; this command never creates or repairs
# configuration, so an absent, malformed, symlinked, hardlinked, or otherwise
# unsafe value is a concrete error rather than an inferred default.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DJ_ROOT="${DJ_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DJ_HOME="${DJ_HOME:-${DJ_ROOT_OVERRIDE:-$DJ_ROOT}}"
CONFIG="${DJ_CONFIG_OVERRIDE:-$DJ_HOME/config}"
DATA="${DJ_DATA_OVERRIDE:-$DJ_HOME/data}"

# shellcheck source=bin/dj-startup-memory-budget-lib.sh
. "$SCRIPT_DIR/dj-startup-memory-budget-lib.sh"

usage() {
  sed -n '2,11{s/^# \{0,1\}//;p;}' "$0"
}

print_error() {
  printf 'startup-memory-budget: %s\n' "$1" >&2
}

read_budget() {
  if ! dj_startup_memory_budget_read "$CONFIG" >/dev/null; then
    print_error "invalid config/$DJ_STARTUP_MEMORY_BUDGET_FILE - $DJ_STARTUP_MEMORY_BUDGET_ERROR"
    return 1
  fi
  printf '%s\n' "$DJ_STARTUP_MEMORY_BUDGET_VALUE"
}

report() {
  local budget bytes tokens presence total=0 shared_tokens=0 role=primary
  if ! budget=$(read_budget); then
    return 2
  fi

  if [ -e "$DJ_HOME/.dj-secondmate-home" ] || [ -L "$DJ_HOME/.dj-secondmate-home" ]; then
    role=secondmate
  fi

  printf 'estimator=ceil(UTF-8 bytes / 3) conservative-local-estimate\n'
  printf 'role=%s\n' "$role"
  printf 'effective_budget_tokens=%s\n' "$budget"
  for file in captain.md captain-shared.md learnings.md; do
    if ! dj_startup_memory_measure_file "$DATA/$file" >/dev/null; then
      print_error "$DJ_STARTUP_MEMORY_BUDGET_ERROR"
      return 2
    fi
    bytes=$DJ_STARTUP_MEMORY_MEASURE_BYTES
    tokens=$DJ_STARTUP_MEMORY_MEASURE_TOKENS
    presence=$DJ_STARTUP_MEMORY_MEASURE_PRESENCE
    total=$((total + tokens))
    [ "$file" != captain-shared.md ] || shared_tokens=$tokens
    printf 'file=data/%s bytes=%s estimated_tokens=%s status=%s\n' \
      "$file" "$bytes" "$tokens" "$presence"
  done
  printf 'total_estimated_tokens=%s\n' "$total"
  if dj_startup_memory_decimal_le "$total" "$budget"; then
    printf 'budget_status=within-budget\n'
  else
    printf 'budget_status=over-budget\n'
  fi
  if [ "$role" = secondmate ] \
    && ! dj_startup_memory_decimal_le "$shared_tokens" "$budget"; then
    printf 'exception=primary-owned-shared-file-alone-exceeds-budget\n'
  fi
}

case "${1:-}" in
  read)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    read_budget
    ;;
  report)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    report
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

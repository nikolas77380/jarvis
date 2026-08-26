#!/usr/bin/env bash
# Print a task's recorded role, from the brief's "Role contract:" line.
# Usage: dj-role.sh <task-id>
# Output: "role=<role> codename=<name>" on one line.
# Exit 0 with output when the brief records a role; exit 3 silently when the
# task is untyped (an untyped task is legal, so its absence is not an error);
# exit 1 loudly when the brief is missing or records an unknown role.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") echo "error: usage: dj-role.sh <task-id>" >&2; exit 1 ;;
esac

# shellcheck source=bin/dj-role-lib.sh
. "$SCRIPT_DIR/dj-role-lib.sh"

DJ_ROOT="${DJ_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DJ_HOME="${DJ_HOME:-${DJ_ROOT_OVERRIDE:-$DJ_ROOT}}"
DATA="${DJ_DATA_OVERRIDE:-$DJ_HOME/data}"

ID=$1
BRIEF="$DATA/$ID/brief.md"
[ -f "$BRIEF" ] || { echo "error: no brief for task '$ID' at $BRIEF" >&2; exit 1; }

ROLE=$(dj_role_from_brief "$BRIEF")
[ -n "$ROLE" ] || exit 3
dj_role_valid "$ROLE" || { echo "error: brief for '$ID' records an unknown role '$ROLE'" >&2; exit 1; }
printf 'role=%s codename=%s\n' "$ROLE" "$(dj_role_codename "$ROLE")"

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/herdr-runtime-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr-runtime-lib.sh"
ID=${1:-}; shift || true
[ -n "$ID" ] && [ "$#" -gt 0 ] || die "usage: agent-send.sh <task-id> <message>"
require_tools
META=$(require_meta "$ID")
[ "$(meta_get "$META" stopped)" != 1 ] || die "task $ID is stopped"
require_fleet_mutation_allowed
herdr --session "$(meta_get "$META" session)" agent prompt "$(meta_get "$META" agent_name)" "$*"

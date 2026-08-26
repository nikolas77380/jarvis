#!/usr/bin/env bash
# dj-marker-lib.sh - compatibility entry point for from-jarvis routing.
#
# bin/dj-operational-input.sh owns current operational-input construction,
# parsing, marker bytes, and the established from-jarvis compatibility
# carrier. Existing callers source this path so they do not need a flag-day
# migration. No side effects on source. set -u / set -e safe.

_FM_MARKER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/dj-operational-input.sh
. "$_FM_MARKER_LIB_DIR/dj-operational-input.sh"
unset _FM_MARKER_LIB_DIR

#!/usr/bin/env bash
# Reserved project id `jarvis` must resolve to the harness root checkout itself (no nested clone),
# while every ordinary project id keeps resolving to projects/<name> — see project_root_path in
# scripts/herdr-runtime-lib.sh. Plan-card lookup must scan the root plan/ in addition to every
# nested projects/*/plan/, refuse an id that exists in both, derive project "jarvis" for a
# root-plan card, and role/agent resolution for "jarvis" must read the root agents/ directly. A
# nested projects/jarvis is a reserved-name collision and must be refused, not silently misread.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
mkdir -p "$REPO/scripts" "$REPO/agents" "$REPO/plan" "$REPO/projects/demo/plan" "$REPO/projects/demo/agents"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$REPO/scripts/"

cd "$REPO"
export HARNESS_HERDR_SESSION=test-harness
. "$REPO/scripts/herdr-runtime-lib.sh"

# --- project_root_path: the one resolver every caller must consume ---

[ "$(project_root_path jarvis)" = "$HARNESS_ROOT" ] || { echo 'project_root_path jarvis did not resolve to the harness root' >&2; exit 1; }
[ "$(project_root_path demo)" = "$HARNESS_ROOT/projects/demo" ] || { echo 'project_root_path demo did not resolve to projects/demo' >&2; exit 1; }

# --- ordinary nested lookup is unaffected ---

printf '# demo task\n**Status:** open · **Owner:** engineer\n' > "$REPO/projects/demo/plan/T01-demo.md"
CARD=$(task_card T01)
[ "$CARD" = "$REPO/projects/demo/plan/T01-demo.md" ] || { echo "task_card T01 resolved wrong: $CARD" >&2; exit 1; }
[ "$(card_project "$CARD")" = demo ] || { echo 'card_project did not resolve nested card to demo' >&2; exit 1; }

# --- root plan/ is now a legitimate, first-class location ---

printf '# root task\n**Status:** open · **Owner:** shell-engineer\n' > "$REPO/plan/T02-root.md"
ROOT_CARD=$(task_card T02)
[ "$ROOT_CARD" = "$REPO/plan/T02-root.md" ] || { echo "task_card T02 did not resolve to root plan/: $ROOT_CARD" >&2; exit 1; }
[ "$(card_project "$ROOT_CARD")" = jarvis ] || { echo 'card_project did not resolve root card to jarvis' >&2; exit 1; }

# Both frozen legacy (Tnn) and session-scoped timestamp ids must resolve at the root, same as nested.
printf '# root timestamp task\n**Status:** open · **Owner:** shell-engineer\n' > "$REPO/plan/260831-2017-002-root-ts.md"
TS_CARD=$(task_card 260831-2017-002)
[ "$TS_CARD" = "$REPO/plan/260831-2017-002-root-ts.md" ] || { echo "task_card did not resolve root timestamp id: $TS_CARD" >&2; exit 1; }
[ "$(card_project "$TS_CARD")" = jarvis ] || { echo 'card_project did not resolve root timestamp card to jarvis' >&2; exit 1; }

# --- an id present in both root and a nested project is ambiguous and must be refused ---

printf '# dup root\n**Status:** open · **Owner:** shell-engineer\n' > "$REPO/plan/dup-id-root.md"
printf '# dup nested\n**Status:** open · **Owner:** engineer\n' > "$REPO/projects/demo/plan/dup-id-nested.md"
if OUT=$(task_card dup-id 2>&1); then
  echo "task_card accepted an id ambiguous between root and nested plans: $OUT" >&2
  exit 1
fi
printf '%s\n' "$OUT" | grep -q 'found 2' || { echo "ambiguity error did not report the duplicate count: $OUT" >&2; exit 1; }

# --- role resolution for jarvis reads the root agents/ directly, no projects/jarvis involved ---

printf '%s\n' '---' 'model: sonnet' '---' 'ROOT shell-engineer' > "$REPO/agents/shell-engineer.md"
ROLE=$(role_path jarvis shell-engineer)
[ "$ROLE" = "$REPO/agents/shell-engineer.md" ] || { echo "role_path jarvis resolved to the wrong file: $ROLE" >&2; exit 1; }
grep -q 'ROOT shell-engineer' "$ROLE" || { echo 'role_path jarvis did not read the root agents/ file' >&2; exit 1; }

# --- a nested projects/jarvis would physically collide with the reserved root id — refuse it ---

mkdir -p "$REPO/projects/jarvis/plan"
printf '# collider\n**Status:** open · **Owner:** engineer\n' > "$REPO/projects/jarvis/plan/T09-collide.md"
COLLIDE_CARD=$(task_card T09)
if OUT=$(card_project "$COLLIDE_CARD" 2>&1); then
  echo "card_project accepted a card under the reserved projects/jarvis: $OUT" >&2
  exit 1
fi
printf '%s\n' "$OUT" | grep -qi 'reserved' || { echo "reserved-collision error did not mention 'reserved': $OUT" >&2; exit 1; }

echo 'root project resolver tests: ok'

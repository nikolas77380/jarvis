#!/usr/bin/env bash
# Mint a new plan card with a session-scoped id and COMMIT the claim immediately.
#
# Why: a card that exists only on disk, untracked by git and absent from plan/INDEX.md, is
# invisible to every other session and worktree — and invisible claims collide. This script closes
# both halves at the moment of creation: the card, its INDEX row, and the regenerated dashboard
# (when the target project has adopted one — see DASHBOARD below) land in ONE commit.
#
# Id shape: <YYMMDD-HHMM>-<NNN>-<slug> (e.g. 260824-1432-001-asset-photo-pool). The minute-granular
# prefix is per-session, so ids never collide across sessions without any coordination; <NNN> is a
# plain counter inside the prefix, starting at 001. A project may also carry a FROZEN legacy id
# scheme (e.g. T01–T48) predating this script — never renamed, never reused — and every matcher in
# this pipeline must keep accepting BOTH shapes: `T<nn>[<letter>]` and `<YYMMDD-HHMM>-<NNN>`.
#
# Usage: scripts/new-task.sh <slug>        e.g. scripts/new-task.sh asset-photo-pool
#
# Requires node_modules (prettier keeps INDEX.md's table format-clean; worktrees often start
# without an install). Fails loudly, never silently skips: every write is verified after it happens.
#
# DASHBOARD (dependency this script does NOT ship): bridgeks' new-task.sh regenerates
# dashboard/index.html via a zero-dependency generator, scripts/dashboard-build.mjs (882 lines,
# parses plan/INDEX.md + every card header into a static HTML page). That generator is ported
# verbatim to templates/dashboard/dashboard-build.mjs in this harness — adoption instructions copy
# it to the target project's scripts/dashboard-build.mjs, same as plan/TEMPLATE.md. This script
# calls scripts/dashboard-build.mjs IN THE TARGET PROJECT (not this harness's copy) and only if it
# is present; if the target project never adopted the dashboard, it prints an explicit skip message
# instead of failing, since the dashboard is optional machinery layered on top of the plan-card
# convention, not a hard requirement of it.

set -euo pipefail

fail() {
  echo "new-task: $*" >&2
  exit 1
}

SLUG="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -n "$SLUG" ] || fail "usage: $(basename "$0") <slug>   e.g. $(basename "$0") asset-photo-pool"
printf '%s' "$SLUG" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' ||
  fail "slug must be lowercase letters/digits with single hyphens, got: $SLUG"

[ -f plan/TEMPLATE.md ] || fail "plan/TEMPLATE.md not found — run from a full checkout (copy templates/plan-task-card.md there first)"
[ -f plan/INDEX.md ] || fail "plan/INDEX.md not found — run from a full checkout"

HAS_DASHBOARD=0
if [ -f scripts/dashboard-build.mjs ]; then
  HAS_DASHBOARD=1
fi

# prettier keeps INDEX.md byte-identical to what a format-check script would demand; a hand-padded
# table row would drift. dashboard-build.mjs itself is zero-dependency, but prettier is not — so the
# install is required up front rather than discovered as a red CI later.
PRETTIER="node_modules/.bin/prettier"
[ -x "$PRETTIER" ] ||
  fail "node_modules/.bin/prettier not found — run the project's install first (worktrees often start without node_modules)"

# This script commits; anything already staged, or unstaged edits to the files it commits, would be
# swept into (or collide with) the claim commit. Refuse instead of guessing.
git diff --cached --quiet ||
  fail "the git index already has staged changes — commit or unstage them first; the claim must be its own commit"
DASHBOARD_DIFF_PATHS="plan/INDEX.md"
if [ "$HAS_DASHBOARD" -eq 1 ]; then
  DASHBOARD_DIFF_PATHS="plan/INDEX.md dashboard/index.html"
fi
# shellcheck disable=SC2086
if ! git diff --quiet -- $DASHBOARD_DIFF_PATHS; then
  fail "plan/INDEX.md or dashboard/index.html has uncommitted edits — commit or stash them first"
fi

PREFIX="$(date +%y%m%d-%H%M)"

# Next unused <NNN> for this prefix. Two invocations inside the same minute get 001 then 002; the
# first free slot after the highest existing one is used, never a gap re-filled.
max=0
for f in plan/"$PREFIX"-[0-9][0-9][0-9]-*.md; do
  [ -e "$f" ] || continue
  n="${f#plan/"$PREFIX"-}"
  n="${n%%-*}"
  n=$((10#$n))
  if [ "$n" -gt "$max" ]; then max="$n"; fi
done
NNN="$(printf '%03d' $((max + 1)))"

ID="$PREFIX-$NNN"
FILE="$ID-$SLUG.md"
CARD="plan/$FILE"
[ ! -e "$CARD" ] || fail "$CARD already exists"

# Card from the template, id and slug filled into the title line. The rest of the template —
# including its HOW-TO-USE comment — is kept for the human/lead to fill in.
sed "1s|^# T0n — short title\$|# $ID — $SLUG|" plan/TEMPLATE.md > "$CARD"
grep -q "^# $ID — $SLUG\$" "$CARD" || {
  rm -f "$CARD"
  fail "template title line did not match — has plan/TEMPLATE.md's first line changed? Update this script's sed to match."
}

# INDEX row, inserted after the LAST existing table row so the table stays contiguous.
TITLE="${SLUG//-/ }"
ROW="| [$ID]($FILE) | $TITLE | open | lead | — | — |"
TMP="plan/INDEX.md.tmp.$$"
trap 'rm -f "$TMP"' EXIT
if ! awk -v row="$ROW" '
  { lines[NR] = $0; if ($0 ~ /^\| \[/) last = NR }
  END {
    if (!last) exit 1
    for (i = 1; i <= NR; i++) { print lines[i]; if (i == last) print row }
  }
' plan/INDEX.md > "$TMP"; then
  rm -f "$CARD"
  fail "could not find any table row (a line starting with '| [') in plan/INDEX.md — row not inserted"
fi
mv "$TMP" plan/INDEX.md
trap - EXIT
grep -qF "]($FILE)" plan/INDEX.md || {
  rm -f "$CARD"
  fail "INDEX row did not land in plan/INDEX.md"
}

# Format the table exactly as the project's format-check will demand it.
"$PRETTIER" --log-level warn --write plan/INDEX.md

ADDED="$CARD plan/INDEX.md"
if [ "$HAS_DASHBOARD" -eq 1 ]; then
  node scripts/dashboard-build.mjs
  ADDED="$ADDED dashboard/index.html"
else
  echo "new-task: scripts/dashboard-build.mjs not found in this project — skipping dashboard regeneration (see templates/dashboard/ in the harness to adopt it)"
fi

# shellcheck disable=SC2086
git add $ADDED

# Belt and braces: the claim this script exists to make must itself pass the integrity check.
scripts/plan-check.sh >/dev/null ||
  fail "scripts/plan-check.sh failed after staging — fix what it reports before re-running"

git commit -m "chore(plan): claim task $ID — $SLUG" ||
  fail "git commit failed — the claim is staged but NOT committed; other sessions cannot see it yet"

echo "claimed $ID → $CARD (committed $(git rev-parse --short HEAD))"
echo "next: fill in the card's Goal/Scope/Owns/Epic/Next, then push so other sessions see the claim"

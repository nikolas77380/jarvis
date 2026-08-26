#!/usr/bin/env bash
# owns-check.sh — no two ACTIVE plan cards may claim the same file.
#
# Why: no id scheme, however collision-proof, stops two cards under perfectly non-colliding
# names from editing the same file concurrently — two differently-named cards can still target the
# very same file (observed on bridgeks: two legacy-id cards both touched one component file
# regardless of their names). Each card declares the files/globs it claims on its `**Owns:**`
# header line (see templates/plan-task-card.md); this script refuses when two cards in an active status declare the same path
# or an overlapping glob, so the collision is caught at dispatch time — before two engineers start
# editing one file in parallel — not as a merge conflict afterwards.
#
# What counts:
#   - Active means `Status:` is open, in-progress, or in-review. A done / cancelled / split /
#     blocked / needs-decision card's `Owns:` line is inert history, never a live claim — two cards
#     may legitimately touch the same file at different points in time.
#   - Cards with no `Owns:` line (a card predating the Owns: convention) are skipped, not errors.
#   - Both id schemes are in scope by construction: the walk covers every plan/*.md, whether the
#     frozen legacy shape (T01–T48, T16a–T16e) or the session-scoped shape
#     (<YYMMDD-HHMM>-<NNN>-<slug>). Do not narrow the glob to one shape — they coexist permanently.
#
# Overlap semantics (deliberately conservative — over-refusing beats a silent double-edit):
#   - identical paths overlap;
#   - a claim with wildcards overlaps any claim it matches as a bash pattern, in either direction
#     (note: in `[[ x == pattern ]]` a `*` crosses `/`, so `dir/*` claims dir's whole subtree);
#   - a wildcard-free claim on a directory overlaps everything under it (`apps/foo` vs
#     `apps/foo/bar.ts`).
#   Two globs that intersect without either matching the other as a literal (`dir/*.ts` vs
#   `dir/a*`) are NOT detected — declare concrete paths, as plan/TEMPLATE.md says, and the
#   question never arises. That limitation stands; the spelling of a single path does not.
#
# Normalization (normalize_claim, applied to EVERY claim before any comparison): every check here
# is a string comparison, so two spellings of one path are two different files as far as the
# overlap test is concerned — and the failure mode is a silent PASS, never an error. One function
# owns the whole question, so a new spelling is fixed in one place rather than in each round's
# comparison.
#
#   It strips surrounding backticks and whitespace (trim_claim), then decides the path by SPLITTING
#   it on `/` and walking the segments: empty segments and `.` are dropped, `..` cancels the segment
#   before it, and what is left is rejoined with `/`. That is what makes it correct by construction.
#   The three earlier rounds each bolted one more substitution onto a chain and each left a spelling
#   the chain could not see: `apps/foo/` (round 1), `./apps/foo/x` (round 2), and — round 3, the
#   reason this is a walk and not a chain — `apps/foo//x`, where `${c//\/\//\/}` does not collapse
#   `//` at all: bash keeps the backslash and the claim came out as `apps/foo\/x`. A chain also
#   never saw `apps/foo/./x`, `apps/../apps/foo/x`, or `.//apps/foo/x` (which it turned into the
#   ABSOLUTE `/apps/foo/x`). Segment contents are never interpreted, so glob characters pass through
#   untouched and a pattern claim still reaches claims_overlap as a pattern.
#
# Invalid claims — REJECTED (exit 2), never silently accepted. A claim is invalid when it is
# absolute (`/apps/x`), when it escapes the repo root (`../outside`, a `..` with nothing before it),
# or when it resolves to the repo root itself (`.`, `./`, `apps/..`). The last is the one worth
# spelling out: a card that owns the whole repository is a briefing error, not a real claim, and the
# two alternatives are both worse. Accepting it as `` would drop it (silent pass, the exact failure
# this script exists to prevent); treating it as "owns everything" would overlap every other active
# card and bury the actual mistake under one OVERLAP line per card. Exit 2 is the same class as a
# bad plan-dir argument: the input is malformed, so there is no verdict to give. A blank claim
# (`a, , b` — a stray comma) is not a claim at all and is skipped, not rejected.
#
# NOT in scope, by explicit user decision (see the plan card that introduced this check on
# bridgeks): comparing declared ownership against a PR's actual diff in CI — it fires on legitimate
# incidental edits. Do not re-propose it here.  # project-specific: link your own project's decision card if you keep one
#
# Usage: scripts/owns-check.sh [plan-dir]
#        plan-dir defaults to plan/; an alternative dir exists so tests can run against fixture
#        cards without leaving stray files under plan/ (scripts/plan-check.sh fails on those).
#        The script cds to the repo root first, so a RELATIVE plan-dir resolves against the repo
#        root, not the caller's CWD — pass an absolute path when the fixtures live elsewhere.
#        scripts/test/owns-check.test.sh drives it that way; run it after any change here.
# Exits 0 when clean, 1 with a line per overlap naming both cards and both claims otherwise.
#        (2 for a bad plan-dir argument or an invalid claim on an active card — malformed input,
#        not a verdict. See "Invalid claims" above.)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLAN_DIR="${1:-plan}"
[ -d "$PLAN_DIR" ] || {
  echo "owns-check: $PLAN_DIR is not a directory" >&2
  exit 2
}

# Strip the decoration a card writes around a claim: backticks and surrounding whitespace. Split out
# so the invalid-claim message can echo what the author actually wrote, minus the markup, without a
# second spelling of the strip.
trim_claim() {
  local c="$1"
  c="${c//\`/}"
  c="${c#"${c%%[![:space:]]*}"}" # leading whitespace
  c="${c%"${c##*[![:space:]]}"}" # trailing whitespace
  printf '%s' "$c"
}

# The single spelling authority — see "Normalization" in the header. Every claim goes through this
# before it is stored, so nothing downstream compares raw text.
# Prints the normalized claim and returns 0; prints nothing and returns 0 for a blank claim (skip);
# returns 1 for an invalid claim (absolute, escaping the root, or resolving TO the root).
normalize_claim() {
  local c
  c="$(trim_claim "$1")"
  [ -n "$c" ] || return 0            # a stray comma, not a claim
  case "$c" in /*) return 1 ;; esac  # absolute: every claim is repo-relative

  # IFS stays '/' for the whole function (it is local, so it is restored on return): it splits the
  # claim into segments below and joins the survivors back at the end.
  local -a segs=() out=()
  local seg
  local IFS='/'
  read -r -a segs <<<"$c"
  for seg in ${segs[@]+"${segs[@]}"}; do
    case "$seg" in
      '' | '.') continue ;; # 'a//b' and 'a/./b' are both 'a/b'
      '..')
        [ "${#out[@]}" -gt 0 ] || return 1 # nothing to cancel: the claim escapes the repo root
        unset 'out[${#out[@]} - 1]'
        ;;
      *) out+=("$seg") ;; # never interpreted — globs pass through as written
    esac
  done
  [ "${#out[@]}" -gt 0 ] || return 1 # resolved to the repo root itself
  printf '%s' "${out[*]}"
}

# One claim per element, kept in two parallel arrays: the card that made it and the path/glob.
claim_cards=()
claim_paths=()
active_cards=0

for f in "$PLAN_DIR"/*.md; do
  [ -e "$f" ] || continue
  base="${f##*/}"
  case "$base" in
    INDEX.md | TEMPLATE.md) continue ;;
  esac

  # Active? The status value is everything after '**Status:**' up to the ' · Owner' separator;
  # its first token is the state ("done (cancelled …)" is done). Anything but the three live
  # states makes every claim on the card inert.
  status_line="$(grep -m1 '^\*\*Status:\*\*' "$f" || true)"
  [ -n "$status_line" ] || continue
  status="$(printf '%s' "$status_line" | sed -E 's/^\*\*Status:\*\* *//; s/ *·.*$//; s/^\**([a-zA-Z-]+)\**.*/\1/')"
  case "$status" in
    open | in-progress | in-review) ;;
    *) continue ;;
  esac
  active_cards=$((active_cards + 1))

  # Claims: the Owns line, comma-separated, backticks optional. No line → a card predating the Owns: convention, skipped.
  owns_line="$(grep -m1 '^\*\*Owns:\*\*' "$f" || true)"
  [ -n "$owns_line" ] || continue
  owns="$(printf '%s' "$owns_line" | sed 's/^\*\*Owns:\*\* *//')"
  while IFS= read -r raw; do
    if ! claim="$(normalize_claim "$raw")"; then
      echo "owns-check: $f declares an invalid Owns claim: '$(trim_claim "$raw")'" >&2
      echo "A claim is a repo-relative path or glob under the repo root: not absolute, not escaping" >&2
      echo "it, and not the root itself (a card cannot own the whole repository). Fix that card's" >&2
      echo "Owns: line." >&2
      exit 2
    fi
    [ -n "$claim" ] || continue
    case "$claim" in
      *'<'* | *'>'*) continue ;; # an unfilled template placeholder is not a claim
    esac
    claim_cards+=("$f")
    claim_paths+=("$claim")
  done < <(printf '%s\n' "$owns" | tr ',' '\n')
done

# Do two claims cover at least one common file? See "Overlap semantics" above.
claims_overlap() {
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 0
  # shellcheck disable=SC2053 # unquoted RHS is the point: the claim is a pattern
  [[ "$a" == $b ]] && return 0
  # shellcheck disable=SC2053
  [[ "$b" == $a ]] && return 0
  case "$a" in "$b"/*) return 0 ;; esac
  case "$b" in "$a"/*) return 0 ;; esac
  return 1
}

overlaps=0
n=${#claim_paths[@]}
i=0
while [ "$i" -lt "$n" ]; do
  j=$((i + 1))
  while [ "$j" -lt "$n" ]; do
    if [ "${claim_cards[$i]}" != "${claim_cards[$j]}" ] &&
      claims_overlap "${claim_paths[$i]}" "${claim_paths[$j]}"; then
      echo "OVERLAP  ${claim_cards[$i]} and ${claim_cards[$j]} are both active and both claim the same file: '${claim_paths[$i]}' overlaps '${claim_paths[$j]}'"
      overlaps=$((overlaps + 1))
    fi
    j=$((j + 1))
  done
  i=$((i + 1))
done

if [ "$overlaps" -gt 0 ]; then
  echo
  echo "owns-check: $overlaps overlapping claim(s). Two active cards must never own one file —" >&2
  echo "re-scope one card's Owns: line, or sequence them (one card Depends on the other, and only" >&2
  echo "one is open/in-progress/in-review at a time)." >&2
  exit 1
fi

echo "owns-check: ok — no overlapping claims among $active_cards active card(s), ${#claim_paths[@]} claim(s)"

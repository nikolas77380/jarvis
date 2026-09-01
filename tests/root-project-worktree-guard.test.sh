#!/usr/bin/env bash
# A root-project (`jarvis`) task worktree is a linked worktree that carries the harness's own
# scripts/ — before this guard, scripts/herdr-runtime-lib.sh's own BASH_SOURCE-derived HARNESS_ROOT
# resolved to the worktree itself, not the main checkout. That silently forks a second fleet: a
# script run from inside the worktree would create its own nested .harness-worktrees/.harness-state
# and dispatch against them, invisible to the real runtime. This hazard exists only for the reserved
# root project — a nested project's own worktree never contains the harness's own scripts/. The fix
# detects a linked worktree (`.git` is a file, not a directory) and re-resolves HARNESS_ROOT to the
# main checkout via `git rev-parse --path-format=absolute --git-common-dir`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
mkdir -p "$REPO/scripts" "$REPO/plan" "$REPO/agents"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/fleet-snapshot.sh" \
  "$ROOT/scripts/harness-observe.sh" "$REPO/scripts/"

cd "$REPO"
git init -q
git config user.email test@example.com
git config user.name Test
printf '# root task\n**Status:** open · **Owner:** shell-engineer\n' > plan/T01-root.md
git add scripts plan
git commit -qm initial

WORKTREE="$TMP/linked-worktree"
git worktree add -q -b harness/T01 "$WORKTREE" HEAD

# Both sides are normalized with `pwd -P` before comparison: git's own path resolution (used by the
# guard) and the shell's logical $PWD (used elsewhere) can disagree purely on symlink form — e.g.
# macOS resolves a mktemp path under /var to /private/var — which is incidental to this test, not
# the behaviour under test.
realpath_of() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }
REPO_REAL=$(realpath_of "$REPO")

# --- from inside the linked worktree, HARNESS_ROOT/STATE/WORKTREES must resolve to the main checkout ---

OUT=$(cd "$WORKTREE" && HARNESS_HERDR_SESSION=test-harness bash -c \
  '. scripts/herdr-runtime-lib.sh && printf "%s\n%s\n%s\n" "$HARNESS_ROOT" "$HARNESS_STATE" "$HARNESS_WORKTREES"')
GOT_ROOT=$(realpath_of "$(sed -n 1p <<<"$OUT")")
GOT_STATE_PARENT=$(realpath_of "$(dirname "$(sed -n 2p <<<"$OUT")")")/$(basename "$(sed -n 2p <<<"$OUT")")
GOT_WORKTREES_PARENT=$(realpath_of "$(dirname "$(sed -n 3p <<<"$OUT")")")/$(basename "$(sed -n 3p <<<"$OUT")")
[ "$GOT_ROOT" = "$REPO_REAL" ] \
  || { echo "HARNESS_ROOT from inside a linked worktree did not resolve to the main checkout: $GOT_ROOT" >&2; exit 1; }
[ "$GOT_STATE_PARENT" = "$REPO_REAL/.harness-state" ] \
  || { echo "HARNESS_STATE from inside a linked worktree did not resolve to the main checkout: $GOT_STATE_PARENT" >&2; exit 1; }
[ "$GOT_WORKTREES_PARENT" = "$REPO_REAL/.harness-worktrees" ] \
  || { echo "HARNESS_WORKTREES from inside a linked worktree did not resolve to the main checkout: $GOT_WORKTREES_PARENT" >&2; exit 1; }

# --- task_card resolved from inside the worktree also lands in the main checkout, not the worktree ---

CARD=$(cd "$WORKTREE" && bash -c '. scripts/herdr-runtime-lib.sh && task_card T01')
CARD_REAL=$(realpath_of "$(dirname "$CARD")")/$(basename "$CARD")
[ "$CARD_REAL" = "$REPO_REAL/plan/T01-root.md" ] \
  || { echo "task_card from inside a linked worktree did not resolve to the main checkout: $CARD_REAL" >&2; exit 1; }

# --- an ordinary (non-linked) checkout is unaffected: HARNESS_ROOT still resolves to itself ---

OUT2=$(HARNESS_HERDR_SESSION=test-harness bash -c '. scripts/herdr-runtime-lib.sh && printf "%s\n" "$HARNESS_ROOT"')
[ "$(realpath_of "$OUT2")" = "$REPO_REAL" ] || { echo "HARNESS_ROOT from the main checkout itself changed: $OUT2" >&2; exit 1; }

# --- fleet-mutating entry points must fail fast from inside the linked worktree, before mutating anything ---

MUTATE_ERR=$(mktemp)
if (cd "$WORKTREE" && HARNESS_HERDR_SESSION=test-harness HARNESS_STATE_DIR="$TMP/unused-state" bash -c \
  '. scripts/herdr-runtime-lib.sh && . scripts/harness-state-lib.sh && state_lock_acquire T01') >/dev/null 2>"$MUTATE_ERR"; then
  echo 'state_lock_acquire unexpectedly succeeded from inside a linked Jarvis task worktree' >&2
  cat "$MUTATE_ERR" >&2
  exit 1
fi
grep -q 'linked Jarvis task worktree' "$MUTATE_ERR" \
  || { echo "guard refusal did not name the linked worktree hazard: $(cat "$MUTATE_ERR")" >&2; exit 1; }
grep -q 'canonical checkout' "$MUTATE_ERR" \
  || { echo "guard refusal did not direct the caller to the canonical checkout: $(cat "$MUTATE_ERR")" >&2; exit 1; }
[ ! -e "$TMP/unused-state/locks/T01.lock" ] \
  || { echo 'state_lock_acquire created a lock despite refusing' >&2; exit 1; }
rm -f "$MUTATE_ERR"

# --- read-only inspection remains usable from inside the linked worktree: sourcing alone must not die ---

(cd "$WORKTREE" && HARNESS_HERDR_SESSION=test-harness bash -c \
  '. scripts/herdr-runtime-lib.sh && . scripts/harness-state-lib.sh') \
  || { echo 'sourcing the runtime libs from inside a linked worktree unexpectedly failed' >&2; exit 1; }

# --- fleet-snapshot.sh must consume the same validated resolver, not its own BASH_SOURCE-derived root,
#     so it cannot split-brain against the canonical checkout when run directly from the worktree ---

printf '# root task 2\n**Status:** open · **Owner:** shell-engineer\n' > "$REPO/plan/T02-canonical-only.md"
git -C "$REPO" add plan/T02-canonical-only.md
git -C "$REPO" commit -qm 'card added to the canonical checkout only, after the worktree was created'
[ ! -f "$WORKTREE/plan/T02-canonical-only.md" ] \
  || { echo 'test setup bug: the new card should not exist in the linked worktree checkout' >&2; exit 1; }

SNAPSHOT=$(cd "$WORKTREE" && scripts/fleet-snapshot.sh --json)
printf '%s' "$SNAPSHOT" | jq -e '.tasks[] | select(.task == "T02-canonical-only")' >/dev/null \
  || { echo 'fleet-snapshot.sh run from inside the linked worktree did not see the canonical-only card — split-brain' >&2; printf '%s\n' "$SNAPSHOT" >&2; exit 1; }

# --- a submodule also has `.git` as a file, but must never be mistaken for a linked worktree: its
#     git-dir and git-common-dir are the same path, unlike a genuine linked worktree's ---

SUPER="$TMP/super"
mkdir -p "$SUPER"
cd "$SUPER"
git init -q
git config user.email test@example.com
git config user.name Test
git commit -q --allow-empty -m 'super initial'
git -c protocol.file.allow=always submodule add -q "$REPO" harness-sub >/dev/null

SUB_REAL=$(realpath_of "$SUPER/harness-sub")
OUT3=$(cd "$SUPER/harness-sub" && HARNESS_HERDR_SESSION=test-harness bash -c \
  '. scripts/herdr-runtime-lib.sh && printf "%s\n%s\n" "$HARNESS_ROOT" "$IS_JARVIS_LINKED_WORKTREE"')
GOT_ROOT3=$(realpath_of "$(sed -n 1p <<<"$OUT3")")
GOT_FLAG3=$(sed -n 2p <<<"$OUT3")
[ "$GOT_ROOT3" = "$SUB_REAL" ] \
  || { echo "HARNESS_ROOT from inside a submodule was redirected instead of staying put: $GOT_ROOT3" >&2; exit 1; }
[ "$GOT_FLAG3" = false ] \
  || { echo 'a submodule checkout was mistaken for a linked Jarvis worktree' >&2; exit 1; }
case "$GOT_ROOT3" in
  */.git/modules/*) echo "HARNESS_ROOT from inside a submodule resolved into .git/modules: $GOT_ROOT3" >&2; exit 1 ;;
esac

echo 'root project worktree guard tests: ok'

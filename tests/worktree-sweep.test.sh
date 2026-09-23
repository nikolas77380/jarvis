#!/usr/bin/env bash
# Every safety rule the sweep claims, demonstrated against throwaway worktrees built here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/harness"
ORIGIN="$TMP/origin.git"
PROJECT="$REPO/projects/demo"
WT="$REPO/.harness-worktrees/demo"
mkdir -p "$REPO/scripts" "$REPO/.harness-state" "$WT" "$TMP/bin"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/worktree-reclaim-lib.sh" \
   "$ROOT/scripts/worktree-sweep.sh" "$REPO/scripts/"
chmod +x "$REPO/scripts/worktree-sweep.sh"
git -C "$REPO" init -q 2>/dev/null || true

# A Herdr stub: it answers for exactly one agent name, so the test can distinguish an agent that is
# still running from one whose metadata survived a process that did not.
cat > "$TMP/bin/herdr" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = h_live ]; then
    printf '{"result":{"agent":{"agent_status":"working"}}}\n'
    exit 0
  fi
done
exit 1
STUB
chmod +x "$TMP/bin/herdr"
PATH="$TMP/bin:$PATH"; export PATH

git init -q --bare "$ORIGIN"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q -b main
git -C "$PROJECT" config user.email test@example.com
git -C "$PROJECT" config user.name Test
git -C "$PROJECT" remote add origin "$ORIGIN"
printf 'node_modules/\n' > "$PROJECT/.gitignore"
printf '# demo\n' > "$PROJECT/README.md"
git -C "$PROJECT" add .gitignore README.md
git -C "$PROJECT" commit -qm initial
git -C "$PROJECT" push -q origin main
git -C "$PROJECT" fetch -q origin

make_worktree() { git -C "$PROJECT" worktree add -q -b "harness/$1" "$WT/$1" main; }
for NAME in clean dirty unpushed content-upstream stub untracked live dead rescueable; do
  make_worktree "$NAME"
done

export HARNESS_STATE_DIR="$REPO/.harness-state"
export HARNESS_WORKTREE_DIR="$REPO/.harness-worktrees"
SWEEP=("$REPO/scripts/worktree-sweep.sh" --root "$WT" --older-than 0 --json)

verdict() { jq -r --arg w "$WT/$1" '.worktrees[]|select(.worktree==$w)|[.blockers[].kind]|sort|join(",")'; }
action() { jq -r --arg w "$WT/$1" '.worktrees[]|select(.worktree==$w)|.action'; }
detail() { jq -r --arg w "$WT/$1" --arg k "$2" '.worktrees[]|select(.worktree==$w)|.blockers[]|select(.kind==$k)|.detail'; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- SAFETY CASE 1: modified tracked files ------------------------------------------------------
printf 'edited in place\n' >> "$WT/dirty/README.md"

# --- SAFETY CASE 2a: a commit that is genuinely only here ---------------------------------------
printf 'real work\n' > "$WT/unpushed/feature.txt"
git -C "$WT/unpushed" add feature.txt
git -C "$WT/unpushed" commit -qm 'unpushed work'

# --- SAFETY CASE 2b: a local commit whose CONTENT is already upstream ---------------------------
# Reachability alone would condemn this: no remote ref reaches its sha. It must survive on content.
printf 'shared\n' > "$WT/content-upstream/shared.txt"
git -C "$WT/content-upstream" add shared.txt
git -C "$WT/content-upstream" commit -qm 'shared change'
git -C "$PROJECT" cherry-pick "$(git -C "$WT/content-upstream" rev-parse HEAD)" >/dev/null
git -C "$PROJECT" push -q origin main
git -C "$PROJECT" fetch -q origin

# --- SAFETY CASE 2c: a stub commit that changes nothing -----------------------------------------
git -C "$WT/stub" commit -q --allow-empty -m 'stub'

# --- SAFETY CASE 3: untracked content git has never heard of ------------------------------------
# The gitignored node_modules must NOT block; the demo screenshots must.
mkdir -p "$WT/untracked/demo" "$WT/untracked/node_modules/pkg"
printf 'screenshot bytes\n' > "$WT/untracked/demo/run-description.md"
printf 'junk\n' > "$WT/untracked/node_modules/pkg/index.js"
mkdir -p "$WT/clean/node_modules/pkg"
printf 'junk\n' > "$WT/clean/node_modules/pkg/index.js"
mkdir -p "$WT/rescueable/demo"
printf 'irreplaceable\n' > "$WT/rescueable/demo/notes.md"

# --- live vs dead agent -------------------------------------------------------------------------
cat > "$REPO/.harness-state/live.meta" <<EOF
schema=harness-herdr-task.v1
task=live
project=demo
worktree=$WT/live
agent_name=h_live
session=test
stopped=0
EOF
cat > "$REPO/.harness-state/dead.meta" <<EOF
schema=harness-herdr-task.v1
task=dead
project=demo
worktree=$WT/dead
agent_name=h_dead
session=test
stopped=0
EOF

OUT=$("${SWEEP[@]}")

[ "$(printf '%s' "$OUT" | verdict dirty)" = uncommitted-changes ] \
  || fail "case 1 not detected: $(printf '%s' "$OUT" | verdict dirty)"
printf '%s' "$OUT" | detail dirty uncommitted-changes | grep -q 'README.md' \
  || fail 'case 1 refusal does not name the file'

[ "$(printf '%s' "$OUT" | verdict unpushed)" = unpushed-commits ] \
  || fail "case 2 not detected: $(printf '%s' "$OUT" | verdict unpushed)"
printf '%s' "$OUT" | detail unpushed unpushed-commits | grep -q "$(git -C "$WT/unpushed" rev-parse HEAD | cut -c1-8)" \
  || fail 'case 2 refusal does not name the commit'
[ "$(printf '%s' "$OUT" | action content-upstream)" = reclaimable ] \
  || fail "a commit already upstream by content was wrongly refused: $(printf '%s' "$OUT" | verdict content-upstream)"
[ "$(printf '%s' "$OUT" | action stub)" = reclaimable ] \
  || fail "an empty stub commit was wrongly refused: $(printf '%s' "$OUT" | verdict stub)"

[ "$(printf '%s' "$OUT" | verdict untracked)" = untracked-files ] \
  || fail "case 3 not detected: $(printf '%s' "$OUT" | verdict untracked)"
printf '%s' "$OUT" | detail untracked untracked-files | grep -q 'demo/run-description.md' \
  || fail 'case 3 refusal does not name the file'
printf '%s' "$OUT" | detail untracked untracked-files | grep -q 'node_modules' \
  && fail 'a gitignored node_modules must not block removal'
[ "$(printf '%s' "$OUT" | action clean)" = reclaimable ] \
  || fail "a worktree holding only gitignored output was refused: $(printf '%s' "$OUT" | verdict clean)"

[ "$(printf '%s' "$OUT" | verdict live)" = live-agent ] \
  || fail "a running agent's worktree was not protected: $(printf '%s' "$OUT" | verdict live)"
[ "$(printf '%s' "$OUT" | action dead)" = reclaimable ] \
  || fail "an agent that died without reporting still blocks: $(printf '%s' "$OUT" | verdict dead)"

# --- the age threshold is a backstop for worktrees nothing else can speak for -------------------
AGED=$("$REPO/scripts/worktree-sweep.sh" --root "$WT" --older-than 1 --json)
[ "$(printf '%s' "$AGED" | verdict clean)" = recently-active ] \
  || fail 'a worktree touched today was not held back by the age threshold'

# --- a repository's main checkout is never a candidate ------------------------------------------
MAIN=$("$REPO/scripts/worktree-sweep.sh" --root "$REPO/projects" --older-than 0 --json)
printf '%s' "$MAIN" | jq -e --arg w "$PROJECT" '.worktrees[]|select(.worktree==$w)|.blockers[]|select(.kind=="main-checkout")' >/dev/null \
  || fail 'a main checkout was not refused as such'

# --- dry run must not have touched anything -----------------------------------------------------
for NAME in clean dirty unpushed content-upstream stub untracked live dead rescueable; do
  [ -d "$WT/$NAME" ] || fail "dry run removed $NAME"
done

# --- rescue: untracked content is preserved and reported before the worktree goes ---------------
RESCUE="$TMP/rescued"
"$REPO/scripts/worktree-sweep.sh" --root "$WT/rescueable" --older-than 0 --rescue "$RESCUE" --execute >/dev/null
[ ! -d "$WT/rescueable" ] || fail 'rescue mode did not reclaim the worktree'
find "$RESCUE" -name notes.md | grep -q . || fail 'rescued untracked file was not preserved'

# --- execute: only the genuinely disposable ones go, and no branch is ever deleted --------------
"$REPO/scripts/worktree-sweep.sh" --root "$WT" --older-than 0 --execute >/dev/null
for NAME in clean content-upstream stub dead; do
  [ ! -d "$WT/$NAME" ] || fail "$NAME should have been reclaimed"
  git -C "$PROJECT" show-ref --verify --quiet "refs/heads/harness/$NAME" \
    || fail "reclaiming $NAME deleted its branch"
done
for NAME in dirty unpushed untracked live; do
  [ -d "$WT/$NAME" ] || fail "$NAME was destroyed despite being refused"
done

# --- a refusal is never silent ------------------------------------------------------------------
TEXT=$("$REPO/scripts/worktree-sweep.sh" --root "$WT" --older-than 0)
for KIND in uncommitted-changes unpushed-commits untracked-files live-agent; do
  printf '%s' "$TEXT" | grep -q "refused: $KIND" || fail "the text report does not name $KIND"
done
printf '%s' "$TEXT" | grep -q "$WT/dirty" || fail 'the text report does not say where'

echo 'worktree sweep tests: ok'

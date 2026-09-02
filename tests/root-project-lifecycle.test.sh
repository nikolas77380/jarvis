#!/usr/bin/env bash
# Root onboarding must accept an already-existing root plan/ (this very harness's own plan/ is one)
# instead of refusing like nested onboarding does, and must not require a nested projects/jarvis
# clone. agent-spawn.sh must resolve a root-owned task's worktree and role against the harness root
# itself, and must never touch the main checkout while doing it (git worktree add only ever adds a
# new worktree; it does not check anything out in the directory it is run from).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/templates" "$REPO/agents" "$FAKEBIN"
cp "$ROOT/scripts/onboard-project.sh" "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" \
  "$ROOT/scripts/agent-spawn.sh" "$ROOT/scripts/agent-engine-lib.sh" "$REPO/scripts/"
cp "$ROOT/templates/plan-task-card.md" "$ROOT/templates/plan-INDEX.md" "$ROOT/templates/OVERVIEW.md" "$ROOT/templates/reports-README.md" "$REPO/templates/"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case " $* " in
  *" workspace create "*) printf '%s\n' '{"result":{"workspace":{"workspace_id":"w1"}}}' ;;
  *" tab create "*) printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}' ;;
  *" agent start "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"idle"}}}' ;;
  *" agent prompt "*) printf '%s\n' '{"result":{"agent":{"name":"task_agent","agent_status":"done"}}}' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

cd "$REPO"
git init -q
git config user.email test@example.com
git config user.name Test
printf '# rules\n' > RULES.md
printf '%s\n' '---' 'model: sonnet' '---' 'ROOT shell-engineer' > agents/shell-engineer.md
git add RULES.md agents/shell-engineer.md
git commit -qm initial

# --- root onboarding must ACCEPT an already-existing root plan/, unlike nested onboarding ---

mkdir -p plan reports
printf '# Plan index\n\n| id | task | status | owner | depends on | note |\n| --- | --- | --- | --- | --- | --- |\n| [T01](T01-existing.md) | existing | open | lead | — | — |\n' > plan/INDEX.md
printf '# T01 — existing\n**Status:** open\n' > plan/TEMPLATE.md
git add plan
git commit -qm 'pre-existing root plan'

scripts/onboard-project.sh jarvis

test -f plan/TEMPLATE.md
test -f OVERVIEW.md
test -f reports/README.md
grep -q '\[T01\]' plan/INDEX.md || { echo 'root onboarding clobbered the pre-existing root plan/INDEX.md' >&2; exit 1; }

# Re-running root onboarding must stay idempotent, never refuse like nested onboarding does.
scripts/onboard-project.sh jarvis >/dev/null || { echo 're-running root onboarding unexpectedly failed' >&2; exit 1; }

# --- agent-spawn.sh: a root-owned task resolves against the harness root, not projects/jarvis ---

cat > plan/T05-root-task.md <<'CARD'
# T05 — root task

**Status:** open · **Owner:** shell-engineer
**Next:** dispatch

## Brief — shell-engineer

Do the root thing.
CARD
git add plan/T05-root-task.md
git commit -qm 'root task card'

export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"
export HARNESS_HERDR_SESSION=test-harness

TRACKED_PATHSPEC="RULES.md agents plan templates scripts"
# shellcheck disable=SC2086
PRE_SPAWN_BRANCH=$(git -C "$REPO" branch --show-current)
PRE_SPAWN_HEAD=$(git -C "$REPO" rev-parse HEAD)
# shellcheck disable=SC2086
PRE_SPAWN_STATUS=$(git -C "$REPO" status --porcelain -- $TRACKED_PATHSPEC)

scripts/agent-spawn.sh T05 >/dev/null

git -C "$REPO" show-ref --verify --quiet refs/heads/harness/T05 \
  || { echo 'root task branch harness/T05 was not created against the harness root repo' >&2; exit 1; }
git -C "$REPO" worktree list | grep -q 'T05' \
  || { echo 'root task worktree was not registered against the harness root repo' >&2; exit 1; }

SYSTEM=$(sed -n 's/^system_prompt=//p' .harness-state/T05.meta)
grep -q 'ROOT shell-engineer' "$SYSTEM" || { echo 'root task did not use the root agents/ role file' >&2; exit 1; }

PROJECT_RECORDED=$(sed -n 's/^project_root=//p' .harness-state/T05.meta)
REPO_REAL=$(cd "$REPO" && pwd -P)
[ "$PROJECT_RECORDED" = "$REPO_REAL" ] || { echo "recorded project_root should be the resolved harness root ($REPO_REAL), got: $PROJECT_RECORDED" >&2; exit 1; }

# The main checkout must be left exactly where it was: same branch, same HEAD, same tracked status.
# git worktree add only ever adds a new linked worktree; it must never check anything out here.
[ "$(git -C "$REPO" branch --show-current)" = "$PRE_SPAWN_BRANCH" ] || { echo 'spawning a root task moved the main checkout off its branch' >&2; exit 1; }
[ "$(git -C "$REPO" rev-parse HEAD)" = "$PRE_SPAWN_HEAD" ] || { echo 'spawning a root task advanced the main checkout HEAD' >&2; exit 1; }
# shellcheck disable=SC2086
[ "$(git -C "$REPO" status --porcelain -- $TRACKED_PATHSPEC)" = "$PRE_SPAWN_STATUS" ] \
  || { echo 'spawning a root task left the main checkout dirty' >&2; exit 1; }

echo 'root project lifecycle tests: ok'

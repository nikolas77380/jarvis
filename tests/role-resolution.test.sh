#!/usr/bin/env bash
# Two projects can each instantiate a role with the SAME name (e.g. nextjs-engineer) and mean
# genuinely different things. agent-spawn.sh must read each project's own projects/<p>/agents/<role>.md
# when it exists, and only fall back to the harness-shared agents/<role>.md when it doesn't — never
# let one project's role file shadow another's.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/agents" "$REPO/projects/alpha/plan" "$REPO/projects/beta/plan" "$FAKEBIN"
cp "$ROOT/scripts/agent-spawn.sh" "$ROOT/scripts/agent-engine-lib.sh" "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$REPO/scripts/"

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
printf '%s\n' '# rules' > RULES.md

# Harness-shared fallback role — a generic template, distinct from either project's own override.
printf '%s\n' '---' 'model: sonnet' '---' 'SHARED GENERIC shared-engineer' > agents/shared-engineer.md

# alpha: has its OWN shared-engineer.md — must win over the harness-shared one.
git -C projects/alpha init -q
git -C projects/alpha config user.email test@example.com
git -C projects/alpha config user.name Test
printf '# alpha\n' > projects/alpha/README.md
git -C projects/alpha add README.md
git -C projects/alpha commit -qm initial
mkdir -p projects/alpha/agents
printf '%s\n' '---' 'model: sonnet' '---' 'ALPHA-SPECIFIC shared-engineer' > projects/alpha/agents/shared-engineer.md
cat > projects/alpha/plan/task-a.md <<'CARD'
# Task A
**Status:** open · **Owner:** shared-engineer
**Next:** dispatch

## Brief — shared-engineer

Do the alpha thing.
CARD

# beta: has NO local override — must fall back to the harness-shared role.
git -C projects/beta init -q
git -C projects/beta config user.email test@example.com
git -C projects/beta config user.name Test
printf '# beta\n' > projects/beta/README.md
git -C projects/beta add README.md
git -C projects/beta commit -qm initial
cat > projects/beta/plan/task-b.md <<'CARD'
# Task B
**Status:** open · **Owner:** shared-engineer
**Next:** dispatch

## Brief — shared-engineer

Do the beta thing.
CARD

export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"
export HARNESS_HERDR_SESSION=test-harness

scripts/agent-spawn.sh task-a >/dev/null
scripts/agent-spawn.sh task-b >/dev/null

SYSTEM_A=$(sed -n 's/^system_prompt=//p' .harness-state/task-a.meta)
SYSTEM_B=$(sed -n 's/^system_prompt=//p' .harness-state/task-b.meta)

grep -q 'ALPHA-SPECIFIC shared-engineer' "$SYSTEM_A"
if grep -q 'SHARED GENERIC shared-engineer' "$SYSTEM_A"; then
  echo 'alpha task pulled in the harness-shared role instead of its own override' >&2
  exit 1
fi
grep -q 'SHARED GENERIC shared-engineer' "$SYSTEM_B"
if grep -q 'ALPHA-SPECIFIC shared-engineer' "$SYSTEM_B"; then
  echo "beta task was contaminated by alpha's project-local role" >&2
  exit 1
fi

echo 'role resolution tests: ok'

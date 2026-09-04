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

# --- Global JS/TS role fixtures (260902-1411-001) ---------------------------------------------
# These checks run against the REAL harness-shared agents/ (not the fixture repo above), because
# they assert properties of the actual global role files: valid frontmatter, the chosen model
# tiers, deps-researcher's read-only tool set, routing language in RULES.md/orchestrator.md, and
# the absence of Yavo-specific facts (repo names, paths, domain semantics) in the global roles.

GLOBAL_ROLES=(
  "nestjs-engineer:sonnet"
  "nestjs-reviewer:opus"
  "nextjs-engineer:sonnet"
  "nextjs-reviewer:opus"
  "deps-researcher:sonnet"
)

for entry in "${GLOBAL_ROLES[@]}"; do
  role="${entry%%:*}"
  want_model="${entry##*:}"
  f="$ROOT/agents/$role.md"

  [ -f "$f" ] || { echo "MISSING global role file: $f" >&2; exit 1; }

  # Frontmatter validity: starts with '---', has a closing '---', and a name: field.
  head -1 "$f" | grep -qx -- '---' || { echo "$role: frontmatter must start with ---" >&2; exit 1; }
  awk 'NR==1{next} /^---$/{print NR; exit}' "$f" | grep -q . \
    || { echo "$role: no closing --- for frontmatter" >&2; exit 1; }
  grep -qE '^name: ' "$f" || { echo "$role: frontmatter missing name:" >&2; exit 1; }

  # Model tiers, preserved from Yavo's role set.
  grep -qE "^model: $want_model\$" "$f" \
    || { echo "$role: expected model: $want_model" >&2; exit 1; }
  grep -qE '^codex_model: gpt-5\.6-sol$' "$f" \
    || { echo "$role: expected codex_model: gpt-5.6-sol" >&2; exit 1; }

  # No Yavo-specific facts leaked into the global role: repo names, paths, DB/domain semantics.
  if grep -qiE 'yavo|yavo-api|yavo-admin|yavo-landing|yavo-analyze-worker|nikolas77380' "$f"; then
    echo "$role: contains a Yavo-specific string" >&2
    exit 1
  fi

  # Raw `gh` is never used; gh-axi is the required wrapper wherever GitHub ops are mentioned.
  if grep -qE '(^|[^-])\bgh (pr|issue|repo|api)\b' "$f"; then
    echo "$role: uses raw \`gh\` instead of \`gh-axi\`" >&2
    exit 1
  fi
done

# deps-researcher's tools: line is a DECLARATION the harness runtime does not enforce (nothing in
# engine_start restricts tool access — see RULES.md's note on this), not a runtime restriction. This
# checks that the declaration excludes Edit/Write and that the role says it is read-only, never that
# the runtime actually stops it from writing.
DR="$ROOT/agents/deps-researcher.md"
grep -qE '^tools: ' "$DR" || { echo "deps-researcher: missing tools: line" >&2; exit 1; }
if grep -E '^tools: ' "$DR" | grep -qE '\b(Edit|Write)\b'; then
  echo "deps-researcher: tools line must not grant Edit or Write" >&2
  exit 1
fi
grep -qi 'read-only' "$DR" || { echo "deps-researcher: must state it is read-only" >&2; exit 1; }
grep -qi 'never install' "$DR" || { echo "deps-researcher: must state it never installs" >&2; exit 1; }

# Global fallback behavior for these roles is already exercised end-to-end by the alpha/beta
# project-local-override case above (role_path() resolution), so it is not re-asserted here by
# grepping agent-spawn.sh's source text — that grep matched only a `die` message, not the resolver,
# and broke on a wording change with zero marginal coverage (round 1 review, finding 8).

# Routing language: RULES.md and orchestrator.md must require deps-researcher before adopting or
# replacing an npm package and before a major upgrade, and state patch/minor routes there only on
# compatibility/security uncertainty.
for f in "$ROOT/RULES.md" "$ROOT/agents/orchestrator.md"; do
  grep -qi 'deps-researcher' "$f" || { echo "$f: no deps-researcher routing language" >&2; exit 1; }
  grep -qi 'major' "$f" || { echo "$f: no mention of major upgrades routing to deps-researcher" >&2; exit 1; }
done

echo 'global JS/TS role fixture tests: ok'

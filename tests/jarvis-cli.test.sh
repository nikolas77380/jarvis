#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/bin" "$REPO/scripts" "$REPO/agents" "$REPO/config" "$FAKEBIN"
cp "$ROOT/bin/jarvis" "$REPO/bin/" 2>/dev/null || true
cp "$ROOT/scripts/jarvis-runtime-lib.sh" "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$REPO/scripts/" 2>/dev/null || true
printf '# Rules\n' > "$REPO/RULES.md"
printf '%s\n' '---' 'model: sonnet' 'effort: high' '---' '# Orchestrator' > "$REPO/agents/orchestrator.md"
printf '%s\n' '{"defaultEngine":"claude"}' > "$REPO/config/harness.json"
printf '%s\n' '[mcp_servers.figma]' 'url = "https://mcp.figma.com/mcp"' > "$REPO/config/jarvis-codex.toml"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
args=" $* "
case "$args" in
  *" workspace create "*) printf '%s\n' '{"result":{"workspace":{"workspace_id":"w1"}}}' ;;
  *" tab create "*) printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}' ;;
  *" agent start "*) printf '%s\n' '{"result":{"agent":{"name":"jarvis","agent_status":"idle"}}}' ;;
  *" agent get "*) printf '%s\n' "${FAKE_AGENT_GET:-{\"result\":{\"agent\":{\"agent_status\":\"idle\"}}}}" ;;
  *" agent prompt "*|*" tab focus "*|*" tab close "*) printf '%s\n' '{"result":{"ok":true}}' ;;
  *" session attach "*) printf '%s\n' 'attached' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"
export HARNESS_STATE_DIR="$TMP/state"
export HARNESS_HERDR_SESSION=test-harness
export JARVIS_NO_ATTACH=1
export CODEX_HOME="$TMP/user-codex"
mkdir -p "$CODEX_HOME"
printf '%s\n' '{"test":"credentials"}' > "$CODEX_HOME/auth.json"

"$REPO/bin/jarvis" claude >/dev/null
META="$HARNESS_STATE_DIR/jarvis.meta"
grep -qx 'schema=harness-jarvis.v1' "$META"
grep -qx 'engine=claude' "$META"
grep -qx 'generation=1' "$META"
grep -q -- 'agent start jarvis --kind claude' "$FAKE_HERDR_LOG"
grep -q -- '--permission-mode bypassPermissions' "$FAKE_HERDR_LOG"
if grep -q -- '--permission-mode auto' "$FAKE_HERDR_LOG"; then
  echo 'Jarvis Claude still starts with interactive permissions' >&2
  exit 1
fi

STARTS_BEFORE=$(grep -c ' agent start ' "$FAKE_HERDR_LOG")
"$REPO/bin/jarvis" >/dev/null
test "$(grep -c ' agent start ' "$FAKE_HERDR_LOG")" = "$STARTS_BEFORE"

"$REPO/bin/jarvis" switch codex >/dev/null
grep -qx 'engine=codex' "$META"
grep -qx 'generation=2' "$META"
grep -q -- 'agent start jarvis_g2 --kind codex' "$FAKE_HERDR_LOG"
grep -q -- '--approve-for-me --no-alt-screen' "$FAKE_HERDR_LOG"
if grep -q -- '--ask-for-approval on-request' "$FAKE_HERDR_LOG"; then
  echo 'Jarvis Codex still requires manual approvals' >&2
  exit 1
fi
grep -q -- "tab create .* --env HOME=$HARNESS_STATE_DIR/codex-homes/jarvis/home --env CODEX_HOME=$HARNESS_STATE_DIR/codex-homes/jarvis/state" "$FAKE_HERDR_LOG"
test -L "$HARNESS_STATE_DIR/codex-homes/jarvis/state/auth.json"
test "$(readlink "$HARNESS_STATE_DIR/codex-homes/jarvis/state/auth.json")" = "$CODEX_HOME/auth.json"
grep -Fqx "HOME = \"$HOME\"" "$HARNESS_STATE_DIR/codex-homes/jarvis/state/config.toml"
grep -Fqx 'plugins = false' "$HARNESS_STATE_DIR/codex-homes/jarvis/state/config.toml"
grep -Fqx 'skill_search = false' "$HARNESS_STATE_DIR/codex-homes/jarvis/state/config.toml"
grep -Fqx '[mcp_servers.figma]' "$HARNESS_STATE_DIR/codex-homes/jarvis/state/config.toml"
grep -Fqx 'url = "https://mcp.figma.com/mcp"' "$HARNESS_STATE_DIR/codex-homes/jarvis/state/config.toml"
if grep -q '# Central harness rules' "$FAKE_HERDR_LOG"; then
  echo 'Codex received the full system prompt as visible input' >&2
  exit 1
fi
grep -q 'Jarvis is online. Read memory/captain.md and memory/harness.md' "$FAKE_HERDR_LOG"
if grep -q 'MEMORY CONTEXT' "$FAKE_HERDR_LOG"; then
  echo 'Jarvis startup prompt echoed the full memory dump as visible input' >&2
  exit 1
fi
grep -Fq 'Before taking any action' "$ROOT/AGENTS.md"

"$REPO/bin/jarvis" relaunch >/dev/null
grep -qx 'engine=codex' "$META"
grep -qx 'generation=3' "$META"
grep -q '"action":"relaunch"' "$HARNESS_STATE_DIR/jarvis-history.jsonl"
FAKE_AGENT_GET='{"result":{}}' "$REPO/bin/jarvis" relaunch >/dev/null
grep -qx 'generation=4' "$META"

test "$("$REPO/bin/jarvis" status)" = 'Jarvis: idle · engine=codex · generation=4'
"$REPO/bin/jarvis" stop >/dev/null
grep -qx 'stopped=1' "$META"

mkdir -p "$TMP/zsh"
ZDOTDIR="$TMP/zsh" "$REPO/bin/jarvis" install-alias >/dev/null
ZDOTDIR="$TMP/zsh" "$REPO/bin/jarvis" install-alias >/dev/null
test "$(grep -c '^alias jarvis=' "$TMP/zsh/.zshrc")" = 1
grep -Fq "$REPO/bin/jarvis" "$TMP/zsh/.zshrc"

echo 'jarvis CLI tests: ok'

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

"$REPO/bin/jarvis" claude >/dev/null
META="$HARNESS_STATE_DIR/jarvis.meta"
grep -qx 'schema=harness-jarvis.v1' "$META"
grep -qx 'engine=claude' "$META"
grep -qx 'generation=1' "$META"
grep -q -- 'agent start jarvis --kind claude' "$FAKE_HERDR_LOG"

STARTS_BEFORE=$(grep -c ' agent start ' "$FAKE_HERDR_LOG")
"$REPO/bin/jarvis" >/dev/null
test "$(grep -c ' agent start ' "$FAKE_HERDR_LOG")" = "$STARTS_BEFORE"

"$REPO/bin/jarvis" switch codex >/dev/null
grep -qx 'engine=codex' "$META"
grep -qx 'generation=2' "$META"
grep -q -- 'agent start jarvis_g2 --kind codex' "$FAKE_HERDR_LOG"
grep -q -- '--sandbox workspace-write --ask-for-approval on-request --no-alt-screen' "$FAKE_HERDR_LOG"

test "$("$REPO/bin/jarvis" status)" = 'Jarvis: idle · engine=codex · generation=2'
"$REPO/bin/jarvis" stop >/dev/null
grep -qx 'stopped=1' "$META"

mkdir -p "$TMP/zsh"
ZDOTDIR="$TMP/zsh" "$REPO/bin/jarvis" install-alias >/dev/null
ZDOTDIR="$TMP/zsh" "$REPO/bin/jarvis" install-alias >/dev/null
test "$(grep -c '^alias jarvis=' "$TMP/zsh/.zshrc")" = 1
grep -Fq "$REPO/bin/jarvis" "$TMP/zsh/.zshrc"

echo 'jarvis CLI tests: ok'

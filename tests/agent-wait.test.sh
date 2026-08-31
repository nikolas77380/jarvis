#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/.harness-state" "$FAKEBIN"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/agent-wait.sh" "$ROOT/scripts/quota-resume-lib.sh" "$REPO/scripts/"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_HERDR_LOG:?}"
printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"
case " $* " in
  *" agent wait "*)
    [ "${FAKE_WAIT_FAIL:-0}" != 1 ] || exit 1
    exit 0
    ;;
  *" agent get "*) printf '%s\n' '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

cd "$REPO"
cat > .harness-state/T1.meta <<'EOF'
schema=harness-herdr-task.v1
task=T1
agent_name=h_t1
session=test-harness
stopped=0
EOF

export PATH="$FAKEBIN:$PATH"
export FAKE_HERDR_LOG="$TMP/herdr.log"

OUT=$(scripts/agent-wait.sh T1)
printf '%s\n' "$OUT" | grep -q 'task T1 settled: idle'
grep -q -- 'agent wait h_t1' "$FAKE_HERDR_LOG"
if grep -q -- '--timeout' "$FAKE_HERDR_LOG"; then
  echo 'unexpected --timeout without one being requested' >&2
  exit 1
fi

: > "$FAKE_HERDR_LOG"
scripts/agent-wait.sh T1 --timeout 5000 >/dev/null
grep -q -- 'agent wait h_t1 --timeout 5000' "$FAKE_HERDR_LOG"

sed -i.bak 's/stopped=0/stopped=1/' .harness-state/T1.meta
if scripts/agent-wait.sh T1 >/dev/null 2>&1; then
  echo 'waiting on a stopped task unexpectedly succeeded' >&2
  exit 1
fi

echo 'agent wait tests: ok'

#!/usr/bin/env bash
# session-start.sh and fleet-snapshot.sh must discover the reserved root project's own plan/, the
# same way they already discover every nested projects/<project>/plan/ — see project_root_path in
# scripts/herdr-runtime-lib.sh. Before this fix, session-start.sh only ever built its INDEX paths
# under projects/$PROJECT/plan/, and fleet-snapshot.sh only ever walked projects/*/plan/*.md, so a
# root-owned card (with or without runtime metadata) never showed up in either view.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
FAKEBIN="$TMP/bin"
mkdir -p "$REPO/scripts" "$REPO/plan" "$REPO/projects/demo/plan" "$REPO/memory/projects" "$FAKEBIN"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/harness-state-lib.sh" "$ROOT/scripts/harness-event-lib.sh" \
  "$ROOT/scripts/quota-resume-lib.sh" "$ROOT/scripts/quota-resume-poll.sh" "$ROOT/scripts/events-poll.sh" \
  "$ROOT/scripts/decisions.sh" "$ROOT/scripts/inbox.sh" "$ROOT/scripts/fleet-snapshot.sh" \
  "$ROOT/scripts/harness-observe.sh" "$ROOT/scripts/session-start.sh" "$REPO/scripts/"

cat > "$FAKEBIN/herdr" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case " $* " in
  *" agent get "*) printf '%s\n' '{"result":{}}' ;;
  *) printf '%s\n' '{"result":{}}' ;;
esac
FAKE
chmod +x "$FAKEBIN/herdr"

cd "$REPO"
git init -q
git config user.email test@example.com
git config user.name Test

# A root-owned card, never spawned (no runtime metadata) — the exact gap finding 3 named.
cat > plan/T06-root-fresh.md <<'CARD'
# T06 — root fresh

**Status:** open · **Owner:** shell-engineer
**Next:** dispatch

## Brief — shell-engineer

Do the root thing.
CARD
cat > plan/INDEX.md <<'INDEX'
# Plan index

| id | task | status | owner | depends on | note |
|---|---|---|---|---|---|
| [T06](T06-root-fresh.md) | root fresh | open | shell-engineer | — | — |
INDEX

# A nested project's card, for contrast — must keep showing up exactly as before.
cat > projects/demo/plan/T01-demo.md <<'CARD'
# T01 — demo
**Status:** open · **Owner:** engineer
CARD
cat > projects/demo/plan/INDEX.md <<'INDEX'
# Plan index

| id | task | status | owner | depends on | note |
|---|---|---|---|---|---|
| [T01](T01-demo.md) | demo | open | engineer | — | — |
INDEX
printf '# demo project memory\n' > memory/projects/demo.md

git add plan projects memory
git commit -qm initial

export PATH="$FAKEBIN:$PATH"
export HARNESS_HERDR_SESSION=test-harness

# --- finding 2: session-start.sh must find the root plan/INDEX.md, both explicitly and by default ---

OUT_JARVIS=$(scripts/session-start.sh --project jarvis --no-memory)
grep -q 'T06' <<<"$OUT_JARVIS" \
  || { echo 'session-start.sh --project jarvis did not surface the root plan card' >&2; echo "$OUT_JARVIS" >&2; exit 1; }
grep -q 'not installed' <<<"$OUT_JARVIS" \
  && { echo 'session-start.sh --project jarvis reported the root plan/INDEX.md as not installed' >&2; exit 1; }

OUT_DEFAULT=$(scripts/session-start.sh --no-memory)
grep -q 'T06' <<<"$OUT_DEFAULT" \
  || { echo 'session-start.sh (no --project) omitted the root plan card' >&2; echo "$OUT_DEFAULT" >&2; exit 1; }
grep -q -- '-- jarvis --' <<<"$OUT_DEFAULT" \
  || { echo 'session-start.sh (no --project) did not label the root section jarvis' >&2; exit 1; }
grep -q 'T01' <<<"$OUT_DEFAULT" \
  || { echo 'session-start.sh (no --project) regressed nested project discovery' >&2; exit 1; }
grep -q -- '-- demo --' <<<"$OUT_DEFAULT" \
  || { echo 'session-start.sh (no --project) regressed the nested project section label' >&2; exit 1; }

# --- finding 3: fleet-snapshot.sh must include a root card even with no runtime metadata yet ---

SNAPSHOT=$(scripts/fleet-snapshot.sh --json)
printf '%s' "$SNAPSHOT" | jq -e '.tasks[] | select(.task == "T06-root-fresh")' >/dev/null \
  || { echo 'fleet-snapshot.sh did not include the unspawned root card' >&2; printf '%s\n' "$SNAPSHOT" >&2; exit 1; }
printf '%s' "$SNAPSHOT" | jq -e '.tasks[] | select(.task == "T01-demo")' >/dev/null \
  || { echo 'fleet-snapshot.sh regressed nested project card discovery' >&2; exit 1; }

echo 'root project discovery tests: ok'

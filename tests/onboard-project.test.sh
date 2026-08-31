#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/harness"
mkdir -p "$REPO/scripts" "$REPO/templates" "$REPO/projects/demo"
cp "$ROOT/scripts/onboard-project.sh" "$REPO/scripts/"
cp "$ROOT/templates/plan-task-card.md" "$ROOT/templates/plan-INDEX.md" "$ROOT/templates/OVERVIEW.md" "$ROOT/templates/reports-README.md" "$REPO/templates/"

cd "$REPO"
git -C projects/demo init -q
git -C projects/demo config user.email test@example.com
git -C projects/demo config user.name Test
printf '# demo\n' > projects/demo/README.md
git -C projects/demo add README.md
git -C projects/demo commit -qm initial

# Unrelated pre-existing staged change must survive untouched by onboarding.
printf 'wip\n' > projects/demo/unrelated.swift
git -C projects/demo add unrelated.swift

scripts/onboard-project.sh demo

test -f projects/demo/plan/TEMPLATE.md
test -f projects/demo/plan/INDEX.md
test -f projects/demo/OVERVIEW.md
test -f projects/demo/reports/README.md
if grep -q '\[T01\]' projects/demo/plan/INDEX.md; then
  echo 'illustrative T01 example row was not stripped' >&2
  exit 1
fi

# The onboarding commit must contain exactly the four new paths, nothing else.
FILES=$(git -C projects/demo show --stat --format='' HEAD | grep '|' | awk '{print $1}')
test "$(printf '%s\n' "$FILES" | sort | tr '\n' ' ')" = "$(printf 'OVERVIEW.md\nplan/INDEX.md\nplan/TEMPLATE.md\nreports/README.md\n' | sort | tr '\n' ' ')"

# The unrelated pre-staged file must still be staged, untouched by the onboarding commit.
git -C projects/demo status --short | grep -qx 'A  unrelated.swift'

# Re-running onboarding on an already-onboarded project must refuse, not duplicate.
if scripts/onboard-project.sh demo >/dev/null 2>&1; then
  echo 're-onboarding an already-onboarded project unexpectedly succeeded' >&2
  exit 1
fi

echo 'onboard project tests: ok'

#!/usr/bin/env bash
# Onboard a project clone into the plan/worktree/review pipeline.
#
# Why: a project under projects/<name> with no plan/ has nowhere for the lead to write a brief and
# nothing for scripts/new-task.sh to mint a card into — task_card() also can't ever find a card for
# it (scripts/herdr-runtime-lib.sh scans projects/*/plan/). Observed on Catch: with no plan/, the
# lead had no dispatch path and fell back to editing application code directly on main instead of
# refusing or bootstrapping first. This script is that bootstrap, run once per project.
#
# Installs plan/TEMPLATE.md, plan/INDEX.md (illustrative example row stripped), OVERVIEW.md and
# reports/README.md from templates/, then commits exactly those new paths — never anything else
# already sitting in the project's index or working tree, however dirty (git commit --only). A
# project can have unrelated uncommitted work; onboarding must not sweep it into this commit.
#
# Usage: scripts/onboard-project.sh <project>   e.g. scripts/onboard-project.sh Catch

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "onboard-project: $*" >&2
  exit 1
}

PROJECT="${1:-}"
[ -n "$PROJECT" ] || fail "usage: $(basename "$0") <project>   e.g. $(basename "$0") Catch"
case "$PROJECT" in ''|*[!a-zA-Z0-9._-]*) fail "invalid project name: $PROJECT" ;; esac

PROJECT_ROOT="$ROOT/projects/$PROJECT"
[ -d "$PROJECT_ROOT/.git" ] || [ -f "$PROJECT_ROOT/.git" ] ||
  fail "project clone not found: $PROJECT_ROOT (git clone it under projects/ first)"
[ ! -d "$PROJECT_ROOT/plan" ] || fail "project already has plan/: $PROJECT_ROOT/plan"

for f in plan-task-card.md plan-INDEX.md OVERVIEW.md reports-README.md; do
  [ -f "$ROOT/templates/$f" ] || fail "template missing: templates/$f"
done

mkdir -p "$PROJECT_ROOT/plan" "$PROJECT_ROOT/reports"

NEW_PATHS=()

cp "$ROOT/templates/plan-task-card.md" "$PROJECT_ROOT/plan/TEMPLATE.md"
NEW_PATHS+=(plan/TEMPLATE.md)

# The shipped plan-INDEX.md carries one illustrative example row (T01) — real, not a placeholder to
# fill in. Strip it so a fresh project's INDEX.md starts with zero fake tasks.
grep -v '^| \[T01\]' "$ROOT/templates/plan-INDEX.md" > "$PROJECT_ROOT/plan/INDEX.md"
NEW_PATHS+=(plan/INDEX.md)

if [ ! -f "$PROJECT_ROOT/OVERVIEW.md" ]; then
  cp "$ROOT/templates/OVERVIEW.md" "$PROJECT_ROOT/OVERVIEW.md"
  NEW_PATHS+=(OVERVIEW.md)
fi

if [ ! -f "$PROJECT_ROOT/reports/README.md" ]; then
  cp "$ROOT/templates/reports-README.md" "$PROJECT_ROOT/reports/README.md"
  NEW_PATHS+=(reports/README.md)
fi

git -C "$PROJECT_ROOT" add -- "${NEW_PATHS[@]}"
git -C "$PROJECT_ROOT" commit --only -q -m 'chore: onboard project into harness plan pipeline' -- "${NEW_PATHS[@]}" ||
  fail "commit failed — check $PROJECT_ROOT git identity is configured"

printf 'onboarded: %s\n' "$PROJECT"
printf '%s\n' "${NEW_PATHS[@]}" | sed 's/^/  + /'

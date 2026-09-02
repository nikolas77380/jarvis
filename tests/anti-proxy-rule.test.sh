#!/usr/bin/env bash
# The lead-never-proxies-evidence invariant must live in the rules every agent reads (RULES.md),
# in the orchestrator's own role instructions, and design-qa's role must declare its required
# capability in frontmatter and refuse to let prefetched/unverified evidence back a MATCH/APPROVE.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -q 'never fetches or absorbs external-source evidence' "$ROOT/RULES.md" \
  || { echo "RULES.md is missing the anti-proxy invariant" >&2; exit 1; }
grep -q 'capabilities: figma' "$ROOT/RULES.md" \
  || { echo "RULES.md does not document capability declaration via role frontmatter" >&2; exit 1; }

grep -q 'Never fetch or absorb external-source evidence yourself' "$ROOT/agents/orchestrator.md" \
  || { echo "agents/orchestrator.md is missing the anti-proxy invariant" >&2; exit 1; }

grep -qx 'capabilities: figma' "$ROOT/agents/design-qa.md" \
  || { echo "agents/design-qa.md does not declare its required capability in frontmatter" >&2; exit 1; }
grep -q 'cannot back a `MATCH`' "$ROOT/agents/design-qa.md" \
  || { echo "agents/design-qa.md does not forbid prefetched/unverified evidence from backing MATCH/APPROVE" >&2; exit 1; }

echo 'anti-proxy rule doc tests: ok'

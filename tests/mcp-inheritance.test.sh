#!/usr/bin/env bash
# A newly created task worktree must inherit the PARENT project's project-scoped Claude MCP consent
# keys (mcpServers, enabledMcpjsonServers) from ~/.claude.json, so a child session sees the same
# authorized MCP identity the orchestrator already has — without ever printing a credential/token
# value, and without disturbing any other key already recorded for parent or child.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/scripts"
cp "$ROOT/scripts/herdr-runtime-lib.sh" "$ROOT/scripts/agent-engine-lib.sh" "$REPO/scripts/"

HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR"
PARENT="$TMP/parent-project"
CHILD="$TMP/child-worktree"
SECRET_TOKEN='sk-super-secret-token-do-not-print'

cat > "$HOME_DIR/.claude.json" <<JSON
{
  "projects": {
    "$PARENT": {
      "hasTrustDialogAccepted": true,
      "someUnrelatedParentKey": "parent-value",
      "mcpServers": {
        "figma": {
          "command": "figma-mcp",
          "env": { "FIGMA_TOKEN": "$SECRET_TOKEN" }
        }
      },
      "enabledMcpjsonServers": ["figma"]
    },
    "$CHILD": {
      "hasTrustDialogAccepted": false,
      "someUnrelatedChildKey": "child-value"
    }
  }
}
JSON

(
  # shellcheck source=/dev/null
  . "$REPO/scripts/herdr-runtime-lib.sh"
  # shellcheck source=/dev/null
  . "$REPO/scripts/agent-engine-lib.sh"

  real_user_home() { printf '%s\n' "$HOME_DIR"; }

  OUT=$(claude_inherit_mcp_config "$CHILD" "$PARENT")
  [ -z "$OUT" ] || { echo "claude_inherit_mcp_config printed output: $OUT" >&2; exit 1; }

  # Child now carries the parent's MCP consent keys verbatim.
  CHILD_SERVERS=$(jq -c --arg p "$CHILD" '.projects[$p].mcpServers' "$HOME_DIR/.claude.json")
  PARENT_SERVERS=$(jq -c --arg p "$PARENT" '.projects[$p].mcpServers' "$HOME_DIR/.claude.json")
  [ "$CHILD_SERVERS" = "$PARENT_SERVERS" ] || { echo "child mcpServers does not match parent: $CHILD_SERVERS != $PARENT_SERVERS" >&2; exit 1; }
  CHILD_ENABLED=$(jq -c --arg p "$CHILD" '.projects[$p].enabledMcpjsonServers' "$HOME_DIR/.claude.json")
  [ "$CHILD_ENABLED" = '["figma"]' ] || { echo "child enabledMcpjsonServers not inherited: $CHILD_ENABLED" >&2; exit 1; }

  # Unrelated keys on both sides are untouched.
  [ "$(jq -r --arg p "$CHILD" '.projects[$p].someUnrelatedChildKey' "$HOME_DIR/.claude.json")" = child-value ] \
    || { echo "unrelated child key was disturbed" >&2; exit 1; }
  [ "$(jq -r --arg p "$CHILD" '.projects[$p].hasTrustDialogAccepted' "$HOME_DIR/.claude.json")" = false ] \
    || { echo "unrelated child key hasTrustDialogAccepted was disturbed" >&2; exit 1; }
  [ "$(jq -r --arg p "$PARENT" '.projects[$p].someUnrelatedParentKey' "$HOME_DIR/.claude.json")" = parent-value ] \
    || { echo "parent entry was mutated" >&2; exit 1; }

  # The secret token value must never appear anywhere except inside the JSON file itself (i.e. the
  # function must not have echoed, logged, or otherwise surfaced it elsewhere).
  if grep -R "$SECRET_TOKEN" "$TMP" --include='*' -l 2>/dev/null | grep -v "$HOME_DIR/.claude.json" >/dev/null; then
    echo "secret token leaked outside the config file" >&2
    exit 1
  fi

  # Empty project_root (e.g. not resolvable) is a safe no-op.
  BEFORE=$(cat "$HOME_DIR/.claude.json")
  claude_inherit_mcp_config "$CHILD" ""
  AFTER=$(cat "$HOME_DIR/.claude.json")
  [ "$BEFORE" = "$AFTER" ] || { echo "empty project_root was not a no-op" >&2; exit 1; }
)

echo 'mcp inheritance tests: ok'

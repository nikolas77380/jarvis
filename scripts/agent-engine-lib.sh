#!/usr/bin/env bash
# Claude/Codex selection and launch inside the single Herdr runtime.

engine_valid() { case "$1" in claude|codex) return 0 ;; *) return 1 ;; esac; }

engine_resolve() {
  local explicit=$1 card=$2 project=$3 engine config
  engine=$explicit
  [ -n "$engine" ] || engine=$(card_field "$card" Engine)
  config="$HARNESS_ROOT/config/projects/$project.json"
  if [ -z "$engine" ] && [ -f "$config" ]; then engine=$(jq -r '.engine // empty' "$config"); fi
  if [ -z "$engine" ] && [ -f "$HARNESS_ROOT/config/harness.json" ]; then
    engine=$(jq -r '.defaultEngine // empty' "$HARNESS_ROOT/config/harness.json")
  fi
  engine=${engine:-claude}
  engine_valid "$engine" || die "engine must be claude or codex, got: $engine"
  printf '%s\n' "$engine"
}

engine_start() {
  local engine=$1 task=$2 role_name=$3 role=$4 worktree=$5 generation=$6 workspace out tab pane name system model effort
  local -a args
  workspace=$(workspace_ensure)
  out=$(herdr_call tab create --workspace "$workspace" --cwd "$worktree" --label "$task-$engine-g$generation" --no-focus) || return 1
  tab=$(printf '%s' "$out" | jq -er '.result.tab.tab_id') || return 1
  pane=$(printf '%s' "$out" | jq -er '.result.root_pane.pane_id') || { herdr_call tab close "$tab" >/dev/null 2>&1 || true; return 1; }
  name=$(agent_runtime_name "$task-$engine-g$generation")
  system="$HARNESS_STATE/$task.g$generation.system.md"
  {
    printf '# Central harness rules\n\n'; cat "$HARNESS_ROOT/RULES.md"
    printf '\n\n# Assigned role: %s\n\n' "$role_name"; cat "$role"
    if [ ! -f "$worktree/CLAUDE.md" ] && [ -f "$worktree/AGENTS.md" ]; then printf '\n\n# Project instructions (AGENTS.md)\n\n'; cat "$worktree/AGENTS.md"; fi
  } > "$system"
  chmod 600 "$system"
  case "$engine" in
    claude)
      model=$(role_field "$role" claude_model); [ -n "$model" ] || model=$(role_field "$role" model)
      effort=$(role_field "$role" claude_effort); [ -n "$effort" ] || effort=$(role_field "$role" effort)
      args=(--append-system-prompt-file "$system" --name "$task" --permission-mode auto)
      [ -z "$model" ] || args+=(--model "$model")
      [ -z "$effort" ] || args+=(--effort "$effort")
      ;;
    codex)
      model=$(role_field "$role" codex_model)
      effort=$(role_field "$role" codex_effort); [ -n "$effort" ] || effort=$(role_field "$role" effort)
      args=(--cd "$worktree" --sandbox workspace-write --ask-for-approval on-request --no-alt-screen)
      [ -z "$model" ] || args+=(--model "$model")
      [ -z "$effort" ] || args+=(-c "model_reasoning_effort=\"$effort\"")
      ;;
  esac
  if ! herdr_call agent start "$name" --kind "$engine" --pane "$pane" -- "${args[@]}" >/dev/null; then
    herdr_call tab close "$tab" >/dev/null 2>&1 || true; return 1
  fi
  jq -nc --arg engine "$engine" --arg name "$name" --arg workspace "$workspace" --arg tab "$tab" --arg pane "$pane" --arg system "$system" \
    '{engine:$engine,name:$name,workspace:$workspace,tab:$tab,pane:$pane,system:$system}'
}

engine_prompt() {
  local engine=$1 name=$2 system=$3 prompt=$4 delivery
  if [ "$engine" = codex ]; then
    delivery=$(cat "$system")$'\n\n# Assignment and handoff\n\n'"$prompt"
  else
    delivery=$prompt
  fi
  herdr_call agent prompt "$name" "$delivery" >/dev/null
}

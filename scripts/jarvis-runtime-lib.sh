#!/usr/bin/env bash
# Persistent interactive Jarvis lifecycle inside the harness Herdr session.

jarvis_meta() { printf '%s/jarvis.meta\n' "$HARNESS_STATE"; }

jarvis_engine_valid() { case "$1" in claude|codex) return 0 ;; *) return 1 ;; esac; }

jarvis_default_engine() {
  local engine=''
  if [ -f "$HARNESS_ROOT/config/harness.json" ]; then
    engine=$(jq -r '.defaultEngine // empty' "$HARNESS_ROOT/config/harness.json")
  fi
  engine=${engine:-claude}
  jarvis_engine_valid "$engine" || die "defaultEngine must be claude or codex, got: $engine"
  printf '%s\n' "$engine"
}

jarvis_system_prompt() {
  local generation=$1 destination
  destination="$HARNESS_STATE/jarvis.g$generation.system.md"
  mkdir -p "$HARNESS_STATE"
  {
    printf '# Identity\n\nYou are Jarvis, the persistent interactive orchestrator for this harness.\n'
    printf 'Talk directly with the user, maintain durable plans and memory, and delegate project work through Herdr.\n\n'
    printf '# Central harness rules\n\n'; cat "$HARNESS_ROOT/RULES.md"
    printf '\n\n# Jarvis role\n\n'; cat "$HARNESS_ROOT/agents/orchestrator.md"
  } > "$destination"
  chmod 600 "$destination"
  printf '%s\n' "$destination"
}

jarvis_launch() {
  local engine=$1 generation=$2 workspace out tab pane name system model effort prompt codex_env
  local -a args tab_args
  workspace=$(workspace_ensure) || return 1
  tab_args=(--workspace "$workspace" --cwd "$HARNESS_ROOT" --label "Jarvis · $engine" --no-focus)
  if [ "$engine" = codex ]; then
    codex_env=$(codex_isolated_environment jarvis "$HARNESS_ROOT") || return 1
    tab_args+=(--env "HOME=$(printf '%s\n' "$codex_env" | sed -n '1p')")
    tab_args+=(--env "CODEX_HOME=$(printf '%s\n' "$codex_env" | sed -n '2p')")
  fi
  out=$(herdr_call tab create "${tab_args[@]}") || return 1
  tab=$(printf '%s' "$out" | jq -er '.result.tab.tab_id') || return 1
  pane=$(printf '%s' "$out" | jq -er '.result.root_pane.pane_id') || { herdr_call tab close "$tab" >/dev/null 2>&1 || true; return 1; }
  if [ "$generation" = 1 ]; then name=jarvis; else name="jarvis_g$generation"; fi
  system=$(jarvis_system_prompt "$generation")
  model=$(role_field "$HARNESS_ROOT/agents/orchestrator.md" "${engine}_model")
  effort=$(role_field "$HARNESS_ROOT/agents/orchestrator.md" "${engine}_effort")
  [ -n "$effort" ] || effort=$(role_field "$HARNESS_ROOT/agents/orchestrator.md" effort)
  case "$engine" in
    claude)
      [ -n "$model" ] || model=$(role_field "$HARNESS_ROOT/agents/orchestrator.md" model)
      args=(--append-system-prompt-file "$system" --name Jarvis --permission-mode bypassPermissions)
      [ -z "$model" ] || args+=(--model "$model")
      [ -z "$effort" ] || args+=(--effort "$effort")
      ;;
    codex)
      args=(--cd "$HARNESS_ROOT" --approve-for-me --no-alt-screen)
      [ -z "$model" ] || args+=(--model "$model")
      [ -z "$effort" ] || args+=(-c "model_reasoning_effort=\"$effort\"")
      ;;
  esac
  if ! herdr_call agent start "$name" --kind "$engine" --pane "$pane" -- "${args[@]}" >/dev/null; then
    herdr_call tab close "$tab" >/dev/null 2>&1 || true
    return 1
  fi
  prompt="Jarvis is online. Read memory/captain.md and memory/harness.md, then run scripts/session-start.sh yourself to reconcile durable harness state (open decisions, unread events, active plan cards, fleet state) - do this now if you have not already this session. Do not print the raw file or command output back to the user: read it privately, greet the user briefly, surface only what actually needs their attention (an open decision, a stalled task, nothing if none), and wait for their request."
  if ! herdr_call agent prompt "$name" "$prompt" >/dev/null; then
    herdr_call tab close "$tab" >/dev/null 2>&1 || true
    return 1
  fi
  jq -nc --arg engine "$engine" --arg generation "$generation" --arg name "$name" --arg workspace "$workspace" --arg tab "$tab" --arg pane "$pane" --arg system "$system" \
    '{engine:$engine,generation:$generation,name:$name,workspace:$workspace,tab:$tab,pane:$pane,system:$system}'
}

jarvis_publish() {
  local launch=$1 meta
  meta=$(jarvis_meta)
  atomic_meta_write "$meta" <<EOF
schema=harness-jarvis.v1
engine=$(printf '%s' "$launch" | jq -r '.engine')
generation=$(printf '%s' "$launch" | jq -r '.generation')
agent_name=$(printf '%s' "$launch" | jq -r '.name')
session=$HARNESS_HERDR_SESSION
workspace=$(printf '%s' "$launch" | jq -r '.workspace')
tab=$(printf '%s' "$launch" | jq -r '.tab')
pane=$(printf '%s' "$launch" | jq -r '.pane')
system_prompt=$(printf '%s' "$launch" | jq -r '.system')
started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
stopped=0
EOF
}

jarvis_attach() {
  local meta=$1 session tab
  session=$(meta_get "$meta" session); tab=$(meta_get "$meta" tab)
  herdr --session "$session" tab focus "$tab" >/dev/null
  [ "${JARVIS_NO_ATTACH:-0}" = 1 ] || herdr session attach "$session"
}

#!/usr/bin/env bash
# Claude/Codex selection and launch inside the single Herdr runtime.

engine_valid() { case "$1" in claude|codex) return 0 ;; *) return 1 ;; esac; }

engine_resolve() {
  local explicit=$1 card=$2 project=$3 engine config jarvis_meta
  engine=$explicit
  [ -n "$engine" ] || engine=$(card_field "$card" Engine)
  config="$HARNESS_ROOT/config/projects/$project.json"
  if [ -z "$engine" ] && [ -f "$config" ]; then engine=$(jq -r '.engine // empty' "$config"); fi
  # No card or project override: default to whichever engine the live orchestrator is currently
  # running as, so a task agent doesn't land on a different engine than the session that dispatched
  # it for no reason a card/project ever chose. A stopped or missing Jarvis falls through below.
  if [ -z "$engine" ]; then
    jarvis_meta="$HARNESS_STATE/jarvis.meta"
    if [ -f "$jarvis_meta" ] && [ ! -L "$jarvis_meta" ] \
      && [ "$(meta_get "$jarvis_meta" schema)" = harness-jarvis.v1 ] \
      && [ "$(meta_get "$jarvis_meta" stopped)" != 1 ]; then
      engine=$(meta_get "$jarvis_meta" engine)
    fi
  fi
  if [ -z "$engine" ] && [ -f "$HARNESS_ROOT/config/harness.json" ]; then
    engine=$(jq -r '.defaultEngine // empty' "$HARNESS_ROOT/config/harness.json")
  fi
  engine=${engine:-claude}
  engine_valid "$engine" || die "engine must be claude or codex, got: $engine"
  printf '%s\n' "$engine"
}

# Claude Code blocks interactively on its own workspace-trust dialog the first time it runs in a
# directory it has never seen — including a freshly `git worktree add`-ed one, even when the worktree
# sits under an already-trusted ancestor: trust does not cascade across a git-repo-root boundary.
# Herdr reports that dialog as pane state "blocked", which agent-spawn.sh has no way to answer, so
# every first spawn into a brand-new task worktree failed outright ("agent_not_ready ... blocked
# during startup"). Every worktree under $HARNESS_WORKTREES was itself just created by this harness
# via `git worktree add` off HEAD of a project it manages — safe to pre-trust unconditionally, unlike
# an arbitrary path. Only ever sets this one flag on this one exact path; never touches anything else
# in the user's global Claude config.
claude_trust_worktree() {
  local worktree=$1 home config tmp
  home=$(real_user_home)
  config="$home/.claude.json"
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$config" ] || return 0
  tmp=$(mktemp "$config.XXXXXX") || return 0
  if jq --arg p "$worktree" '.projects[$p].hasTrustDialogAccepted = true' "$config" > "$tmp" 2>/dev/null \
    && [ -s "$tmp" ]; then
    chmod 600 "$tmp"
    mv "$tmp" "$config"
  else
    rm -f "$tmp"
  fi
}

engine_start() {
  local engine=$1 task=$2 role_name=$3 role=$4 worktree=$5 generation=$6 workspace out tab pane name system model effort codex_env
  local -a args tab_args
  workspace=$(workspace_ensure) || return 1
  name=$(agent_runtime_name "$task-$engine-g$generation")
  tab_args=(--workspace "$workspace" --cwd "$worktree" --label "$task-$engine-g$generation" --no-focus)
  if [ "$engine" = codex ]; then
    codex_env=$(codex_isolated_environment "$name" "$worktree") || return 1
    tab_args+=(--env "HOME=$(printf '%s\n' "$codex_env" | sed -n '1p')")
    tab_args+=(--env "CODEX_HOME=$(printf '%s\n' "$codex_env" | sed -n '2p')")
  fi
  out=$(herdr_call tab create "${tab_args[@]}") || return 1
  tab=$(printf '%s' "$out" | jq -er '.result.tab.tab_id') || return 1
  pane=$(printf '%s' "$out" | jq -er '.result.root_pane.pane_id') || { herdr_call tab close "$tab" >/dev/null 2>&1 || true; return 1; }
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
      # bypassPermissions, not auto: a freshly `git worktree add`-ed task worktree also triggers a
      # second interactive dialog beyond the workspace-trust one claude_trust_worktree answers —
      # "this folder pre-approves N tool permissions in .claude/settings.json, trust this
      # configuration?" — which `--permission-mode auto` does not answer. Herdr reports the pane as
      # permanently "blocked during startup" with nobody able to click through it, and every first
      # spawn into a brand-new task worktree failed outright. Every worktree under
      # $HARNESS_WORKTREES is itself just-created by this harness off HEAD of a project it manages,
      # so its .claude/settings.json is the same already-committed, already-reviewed config as the
      # main checkout's — bypassPermissions removes the unanswerable prompt without granting the
      # agent anything beyond what --permission-mode auto plus that pre-approved allowlist already
      # authorized.
      args=(--append-system-prompt-file "$system" --name "$task" --permission-mode bypassPermissions)
      [ -z "$model" ] || args+=(--model "$model")
      [ -z "$effort" ] || args+=(--effort "$effort")
      ;;
    codex)
      model=$(role_field "$role" codex_model)
      effort=$(role_field "$role" codex_effort); [ -n "$effort" ] || effort=$(role_field "$role" effort)
      args=(--cd "$worktree" --approve-for-me --no-alt-screen)
      [ -z "$model" ] || args+=(--model "$model")
      [ -z "$effort" ] || args+=(-c "model_reasoning_effort=\"$effort\"")
      ;;
  esac
  [ "$engine" != claude ] || claude_trust_worktree "$worktree"
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

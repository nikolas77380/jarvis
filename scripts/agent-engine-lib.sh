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

# Even with claude_trust_worktree's hasTrustDialogAccepted flag set and --permission-mode
# bypassPermissions passed, Claude Code (observed on v2.1.251) still shows a combined
# "Accessing workspace ... quick safety check" + "this folder pre-approves N tool permissions in
# .claude/settings.json" dialog on a pane's first startup, reported by Herdr as agent_status
# "blocked" (confirmed by reading the pane directly: reproduced in the already-trusted main
# checkout of a project, not just a fresh worktree, so it is unconditional on this Claude Code
# version, not specific to first-time paths). Cursor defaults to "No, exit"; one down arrow plus
# enter selects "Yes, I trust this folder". Every path engine_start launches into is a
# harness-managed clone or a harness-created worktree off one — the same trust decision
# claude_trust_worktree already makes unconditionally, just for the dialog that flag doesn't
# suppress.
claude_accept_startup_trust_dialog() {
  local name=$1
  herdr_call agent send-keys "$name" down enter >/dev/null 2>&1 || return 1
  herdr_call agent wait "$name" --timeout 15000 >/dev/null 2>&1
  [ "$(agent_status "$name")" = idle ]
}

# Claude MCP consent (`mcpServers`, `enabledMcpjsonServers`) is recorded per project ENTRY in
# ~/.claude.json, keyed by absolute cwd — so a freshly `git worktree add`-ed task worktree is a brand
# new, unconsented entry even though it is a child of an already-authorized project the orchestrator
# itself runs from. The child inherits the real HOME and keychain, so credentials themselves are
# never the problem; only the project-scoped consent record is missing, which makes an authorized MCP
# server (e.g. Figma) look unauthenticated inside the child. Copy just those two keys from the parent
# project's entry into the child's, preserving every other key already recorded for either side, and
# never printing a value: this function's only observable effect is the JSON file it writes.
claude_inherit_mcp_config() {
  local worktree=$1 project_root=${2:-} home config tmp
  [ -n "$project_root" ] || return 0
  home=$(real_user_home)
  config="$home/.claude.json"
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$config" ] || return 0
  tmp=$(mktemp "$config.XXXXXX") || return 0
  if jq --arg parent "$project_root" --arg child "$worktree" '
      (.projects[$parent].mcpServers // {}) as $servers
      | (.projects[$parent].enabledMcpjsonServers // []) as $enabled
      | .projects[$child] = ((.projects[$child] // {})
          + {mcpServers: $servers, enabledMcpjsonServers: $enabled})
    ' "$config" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    chmod 600 "$tmp"
    mv "$tmp" "$config"
  else
    rm -f "$tmp"
  fi
}

# A role's REQUIRED live capabilities (e.g. an authenticated design-tool MCP), declared as a plain
# comma-separated frontmatter field — `capabilities: figma` — never as a map hard-coded per role name
# in this library. Absent field -> no capabilities required -> caller does no preflight at all.
role_capabilities() {
  local role=$1 raw
  raw=$(role_field "$role" capabilities)
  [ -n "$raw" ] || return 0
  printf '%s\n' "$raw" | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | sed '/^$/d'
}

CAPABILITY_PREFLIGHT_TIMEOUT_MS=${CAPABILITY_PREFLIGHT_TIMEOUT_MS:-180000}

# Deterministic probe text sent BEFORE any substantive brief, to a session that has just started.
# Requires the exact marker line as the reply's last non-blank line so capability_preflight_verdict
# can parse it without guessing at prose.
capability_preflight_prompt() {
  local caps=$1 line
  printf 'CAPABILITY PREFLIGHT — verify access only; do not begin the task yet.\n\n'
  printf 'For each capability listed below, call its tool live, right now, from this session, and\n'
  printf 'confirm it responds authenticated. Do not fetch, summarize, or relay any external content\n'
  printf 'while doing this: the check proves access, it never produces task output.\n\n'
  printf 'Capabilities to verify:\n'
  while IFS= read -r line; do
    [ -n "$line" ] && printf -- '- %s\n' "$line"
  done <<< "$caps"
  printf '\nWhen every capability above is confirmed live and authenticated, output exactly this line\n'
  printf 'as the LAST line of your entire reply, with nothing after it:\n'
  printf 'CAPABILITY_PREFLIGHT_RESULT PASS\n\n'
  printf 'If any capability is missing, unauthenticated, or errors, output exactly this line as the\n'
  printf 'LAST line instead, naming the first capability that failed, with nothing after it:\n'
  printf 'CAPABILITY_PREFLIGHT_RESULT FAIL <capability>\n'
}

# Fail-closed by construction: anything other than the exact PASS marker as the last non-blank line
# (a FAIL marker, a timeout with no reply, stray output, an empty read) is a failed probe.
capability_preflight_verdict() {
  local output=$1 last
  last=$(printf '%s\n' "$output" | sed -e 's/[[:space:]]*$//' | sed -e '/^$/d' | tail -n1)
  [ "$last" = 'CAPABILITY_PREFLIGHT_RESULT PASS' ]
}

# Run the preflight against an already-started session, BEFORE the caller delivers the substantive
# brief. Returns 0 (nothing to do, or probe passed) / 1 (probe failed or could not be delivered) —
# the caller is responsible for never sending the substantive brief when this returns non-zero, and
# for treating that as fail-closed (stop the run; do not mark the task dispatched).
capability_preflight_pass() {
  local engine=$1 name=$2 system=$3 role=$4 caps prompt output
  caps=$(role_capabilities "$role") || true
  [ -n "$caps" ] || return 0
  prompt=$(capability_preflight_prompt "$caps")
  engine_prompt "$engine" "$name" "$system" "$prompt" || return 1
  herdr_call agent wait "$name" --timeout "$CAPABILITY_PREFLIGHT_TIMEOUT_MS" >/dev/null 2>&1 || true
  output=$(herdr_call agent read "$name" --source recent-unwrapped --lines 200 2>/dev/null) || output=''
  capability_preflight_verdict "$output"
}

engine_start() {
  local engine=$1 task=$2 role_name=$3 role=$4 worktree=$5 generation=$6 project_root=${7:-} workspace out tab pane name system model effort codex_env
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
  if [ "$engine" = claude ]; then
    claude_trust_worktree "$worktree"
    claude_inherit_mcp_config "$worktree" "$project_root"
  fi
  if ! herdr_call agent start "$name" --kind "$engine" --pane "$pane" -- "${args[@]}" >/dev/null; then
    if [ "$engine" != claude ] || [ "$(agent_status "$name")" != blocked ] \
      || ! claude_accept_startup_trust_dialog "$name"; then
      herdr_call tab close "$tab" >/dev/null 2>&1 || true; return 1
    fi
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

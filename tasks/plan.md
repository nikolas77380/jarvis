# Live Claude/Codex switching — specification

## Objective

Keep Herdr as the only runtime while allowing each task agent to start on, or safely hand off
between, Claude and Codex without changing its worktree or Git branch.

## Commands and selection

```text
scripts/agent-spawn.sh <task-id> [--engine claude|codex]
scripts/agent-switch.sh <task-id> claude|codex [--note <text>]
```

Selection precedence is explicit flag, task `**Engine:**`, project config `.engine`, global
`config/harness.json.defaultEngine`, then `claude`. Runtime metadata records engine and generation.

## Switch invariants

- Only `idle|done|blocked` may switch; `working|unknown` refuses.
- The new agent starts in a new Herdr tab in the exact recorded worktree.
- HEAD, branch, and porcelain state are captured before launch and must remain unchanged before the
  handoff is submitted.
- Metadata changes atomically only after the target agent is ready. A failed launch closes only the
  new tab and preserves the old binding.
- After publication, the old exact tab is closed best-effort and history is appended. No conversation
  resume is claimed: the new engine receives central rules, role, original brief, Git/state summary,
  and the optional note.
- Clean Slate stage agents remain unchanged in this slice.

## Engine adapters

- Claude: existing append-system-prompt, model, effort, and auto permission flags.
- Codex: interactive Herdr `kind=codex`, workspace-write sandbox, on-request approvals, no alt screen,
  optional model and `model_reasoning_effort`. Central rules and role are delivered in the handoff.

## Testing and boundaries

Fake-Herdr integration covers precedence, spawn kind/metadata, safe-state refusal, successful switch,
generation/history, and launch rollback. Never force-switch a working/unknown agent, switch branches,
modify app files, or grant danger-full-access.

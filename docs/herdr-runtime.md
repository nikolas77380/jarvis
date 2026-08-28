# Herdr runtime specification

## Objective

Run each delegated Claude or Codex agent in its own Herdr tab and keep enough local metadata to inspect,
steer, stop, and recover the fleet from a later orchestrator session. Herdr is the only runtime;
there is no backend abstraction or fallback.

## Commands

```text
scripts/agent-spawn.sh <task-id> [--engine claude|codex]
scripts/agent-switch.sh <task-id> claude|codex [--note <text>]
scripts/agent-list.sh
scripts/agent-state.sh <task-id>
scripts/agent-peek.sh <task-id> [lines]
scripts/agent-send.sh <task-id> <message>
scripts/agent-stop.sh <task-id>
scripts/agent-attach.sh <task-id>
scripts/session-start.sh
```

## State

Projects are central clones under `projects/<project>`. Runtime metadata is local and gitignored under
`.harness-state/`. A task record binds the task card, project clone, worktree, branch, role
definition, engine, generation, unique Herdr agent name, session, workspace, tab, and pane.
Task cards remain the durable project plan; runtime metadata records live execution identity only.

## Behaviour

- Spawn resolves its engine in this order: command-line override, task-card `Engine`, project
  `engine`, global `defaultEngine`, Claude fallback.
- Spawn resolves exactly one task card, reads its `Project` and `Owner`, creates an isolated worktree
  from `projects/<project>`, creates a background Herdr tab, starts the selected engine with the central rules and
  role definition through Herdr, submits the card's `## Brief`, and publishes
  metadata only after every step succeeds.
- A task with published metadata and a readable Herdr agent is not spawned twice.
- State is read from `herdr agent get`; unreadable or missing endpoints report `unknown`, never dead.
- Peek is bounded; send uses Herdr's agent prompt surface; attach focuses the recorded tab.
- Switch is allowed only from `idle`, `done`, or `blocked`. It verifies that branch, HEAD, and dirty
  state do not change during launch, sends a bounded handoff into a fresh engine conversation,
  atomically updates the binding, records JSONL history, and then closes the old tab. Prompt failure
  restores the old binding and closes the new tab.
- Stop closes only the exact tab recorded for the task and marks that binding stopped. Endpoint
  identity remains in metadata for audit; the command never removes the worktree or branch.
- Session start prints active card/runtime reconciliation without mutating Herdr.
- Context-size and spend scripts remain diagnostic. Context size never forces handoff or `/clear`.

## Testing

Shell integration tests run against a fake `herdr` executable and a disposable Git repository. The
fake verifies command shape and deterministic metadata without touching a live Herdr session.

## Boundaries

- Always validate task ids, metadata, and repository-relative paths before acting.
- Never merge, force-push, delete branches, or delete worktrees.
- Never operate on a Herdr tab that is not bound by task metadata created by this runtime.
- Live end-to-end verification must run from a Herdr-managed pane (`HERDR_ENV=1`).

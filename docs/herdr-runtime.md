# Herdr runtime specification

## Objective

Run each delegated Claude or Codex agent in its own Herdr tab and keep enough local metadata to inspect,
steer, stop, and recover the fleet from a later orchestrator session. Herdr is the only runtime;
there is no backend abstraction or fallback.

## Commands

```text
bin/jarvis [claude|codex]
bin/jarvis switch claude|codex
bin/jarvis relaunch
bin/jarvis status|stop|install-alias
scripts/agent-spawn.sh <task-id> [--engine claude|codex]
scripts/agent-switch.sh <task-id> claude|codex [--note <text>]
scripts/quota-resume-poll.sh
scripts/quota-resume-watch.sh
scripts/agent-list.sh
scripts/agent-state.sh <task-id>
scripts/agent-wait.sh <task-id> [--timeout <ms>]
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
Plan cards live inside each project's own checkout, at `projects/<project>/plan/` — never in a
shared `plan/` at the harness root. Herdr resolves a task id by scanning every `projects/*/plan/`
and derives the owning project from where the card was found, because each project's worktrees only
ever contain what its own repo commits, and that is also where that project's claim locks and
review-rounds ledger live.
The persistent interactive orchestrator has a separate `.harness-state/jarvis.meta` binding and
generation history. Calling `jarvis` attaches to that binding instead of creating a duplicate.

## Behaviour

- Jarvis is the human-facing entry point. It starts on the global default engine unless explicitly
  given `claude` or `codex`, loads central rules, the orchestrator role, and the durable session
  snapshot, then attaches the Herdr UI to its tab. Claude Jarvis runs with
  `--permission-mode bypassPermissions`; this applies to the trusted harness checkout only and does
  not change the permission mode of delegated task agents.
- `jarvis switch` creates a fresh Jarvis conversation on the target engine, publishes the new
  binding only after startup succeeds, records history, and closes the previous exact tab.
- Spawn resolves its engine in this order: command-line override, task-card `Engine`, project
  `engine`, the live orchestrator's own current engine (from `.harness-state/jarvis.meta`, when
  Jarvis is running and not stopped), global `defaultEngine`, Claude fallback.
- Spawn resolves exactly one task card by scanning `projects/*/plan/`, derives `Project` from that
  location and reads the card's `Owner`, creates an isolated worktree from `projects/<project>`,
  creates a background Herdr tab, starts the selected engine with the central rules and role
  definition through Herdr, submits the card's `## Brief`, and publishes metadata only after every
  step succeeds.
- A task with published metadata and a readable Herdr agent is not spawned twice.
- State is read from `herdr agent get`; unreadable or missing endpoints report `unknown`, never dead.
- Peek is bounded; send uses Herdr's agent prompt surface; attach focuses the recorded tab.
- Wait blocks on Herdr's `agent wait` until the recorded agent reaches idle, done, or blocked. Run
  it as a background call right after spawn/switch so the lead gets a fresh turn when a specialist
  settles, instead of only reacting the next time the user speaks. A provider quota response is a
  temporary block: wait records its reset deadline, waits, relaunches the same engine against the
  preserved task state, and arms itself again without requiring a human `continue`.
- Quota deadlines are atomic local metadata under `.harness-state/quota/`. Every event poll runs a
  recovery pass, so a due task or Jarvis deadline is resumed even when the original wait process
  disappeared. The external event poll is the supervisor for Jarvis because an exhausted Jarvis
  model cannot relaunch itself. `quota-resume-watch.sh` is the foreground entry point for that
  supervisor; the surrounding harness process manager owns its lifetime and restart policy.
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

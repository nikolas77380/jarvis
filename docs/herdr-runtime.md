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
scripts/agent-cleanup.sh <event-id>
scripts/agent-attach.sh <task-id>
scripts/session-start.sh
```

## State

Projects are central clones under `projects/<project>`. Runtime metadata is local and gitignored under
`.harness-state/`. A task record binds the task card, project clone, worktree, branch, role
definition, engine, generation, unique Herdr agent name, session, workspace, tab, and pane.
Task cards remain the durable project plan; runtime metadata records live execution identity only.
Plan cards live inside each project's own checkout, at `projects/<project>/plan/`, plus one reserved
exception: project id `jarvis` resolves to the harness root checkout itself rather than a nested
clone (`project_root_path` in `scripts/herdr-runtime-lib.sh`; a nested `projects/jarvis` collides
with it and is refused). Herdr resolves a task id by scanning every `projects/*/plan/` plus the
harness root's own `plan/` and derives the owning project from where the card was found, because
each project's worktrees only ever contain what its own repo commits, and that is also where that
project's claim locks and review-rounds ledger live.
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
- Spawn resolves exactly one task card by scanning `projects/*/plan/` plus the harness root's own
  `plan/`, derives `Project` from that location and reads the card's `Owner`, creates an isolated
  worktree from the resolved project root (`project_root_path`; `projects/<project>` for an
  ordinary project, the harness root itself for `jarvis`),
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
- A settled tab is closed only by a deliberate `agent-cleanup.sh <event-id>` call — never
  automatically, and never on detection or event emission alone; nothing in the harness invokes it on
  the lead's behalf. `events-poll.sh` resolves and freezes the producing execution's identity — agent
  name, tab, session, generation — into an `agent-done` event's `identity` field at the moment it
  observes the `done` transition, from an unlocked read of that task's `.meta` as it read then (a
  concurrent handoff rewriting the meta mid-read could yield a chimeric identity, but the match check
  below fails safe on any such mismatch). The event's dedup key includes that generation, so every
  execution generation gets its own event even when HEAD is unchanged across generations — a reviewer
  that commits nothing settles at the same HEAD as the engineer before it, and would otherwise
  silently lose its event to the earlier one's. `agent-cleanup.sh <event-id>` is the only path that
  acts on a frozen identity, and its only trigger is that the event is already acknowledged
  (`inbox.sh acknowledge`) — cleanup refuses on an unacknowledged event, on any type other than
  `agent-done`, and permanently on `blocked` (a live, resumable state that switch/review/quota-resume
  reuse in place, never terminal). It marks the task `stopped=1`, and `agent-review.sh` /
  `agent-switch.sh` both refuse a stopped task outright, so it must only be run for a generation that
  will not be handed to another agent — both of those scripts already close the outgoing tab
  themselves as the last step of their own handoff. Before closing, it re-reads the task's current
  metadata under the task's state lock and requires agent name, tab, session, and generation to still
  equal the event's frozen identity; any mismatch — a newer spawn, switch, review handoff, or
  relaunch — is a safe no-op that leaves the replacement tab untouched. It shares
  `close_recorded_tab()` (`herdr-runtime-lib.sh`) with `agent-stop.sh`, so a settled task ends in the
  identical terminal `stopped=1` state either way. A close failure leaves the acknowledgement and
  metadata exactly as they were, exits non-zero, and is safe to retry by re-running the same command.
  Both the identity match and the already-stopped case are idempotent no-ops, so re-running cleanup on
  an event already acted on is harmless.
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

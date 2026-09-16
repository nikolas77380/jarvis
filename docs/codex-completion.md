# Codex completion watcher

## Purpose

Codex does not receive a new model turn merely because a background shell command finishes. The
opt-in completion watcher is an ordinary foreground Bash process in a tracked Herdr tab. It waits
through the existing `agent-wait.sh` path, including quota recovery, then sends one bounded prompt
to an explicitly captured Codex recipient.

The watcher does not run another model, infer a recipient from UI focus, change the global Herdr
session default, validate a PR, or replace the existing review flow.

## Registration and status

Run all mutating commands from the canonical harness checkout. A linked Jarvis task worktree is
readable but deliberately cannot register or reconcile watcher state.

```bash
scripts/codex-completion-watch.sh start <task-id> --session <session> --pane <codex-pane-id>
scripts/codex-completion-watch.sh status <task-id>
```

`start` is foreground and should be run in its own tracked Herdr tab. The session may be `default`
or a named session. The pane must contain the intended Codex lead and expose a stable
`agent_session.value` through `herdr agent get`. Registration captures the task generation, source
agent binding, canonical metadata and report paths, recipient pane, and recipient session identity.
A second `start` for the same task is rejected.

State is stored atomically under `.harness-state/codex-completion/<task-id>.meta`:

- `pending`: registered and waiting for the source task.
- `waiting`: the Codex recipient is working or blocked; no prompt was sent.
- `delivering`: the prompt call began. A dead process in this state has an ambiguous outcome.
- `delivered`: Herdr accepted the completion prompt.
- `failed`: no prompt was attempted; `detail` records why.
- `uncertain`: a prompt was attempted but its result cannot prove non-delivery.

The prompt contains only the task id, canonical task metadata path, canonical report path, and the
instruction to checkpoint and continue the existing review and validation workflow. Specialist
terminal output is never forwarded.

## Reconciliation and recovery

```bash
scripts/codex-completion-watch.sh reconcile <task-id>
scripts/codex-completion-watch.sh reconcile <task-id> --retry
scripts/codex-completion-watch.sh reconcile <task-id> --delivered
scripts/codex-completion-watch.sh reconcile <task-id> --supersede
```

Plain `reconcile` is non-delivering. If a `delivering` process is gone, it records `uncertain` and
does not resend. Inspect the Codex transcript and Herdr state before choosing:

- `--delivered` records that an uncertain attempt arrived; it sends nothing.
- `--retry` is an explicit new attempt for the same captured task generation and recipient identity.
  Use it after resolving a blocked recipient or a transient pre-delivery failure. On `uncertain`, it
  accepts the risk of a duplicate prompt; the watcher never makes that choice automatically.
- `--supersede` archives any non-delivered claim and removes the active claim. Use it when the task
  generation or recipient conversation was intentionally replaced, then issue a fresh `start` with
  the new explicit session and pane. Delivered claims cannot be superseded.

If quota recovery relaunches the source agent, the watcher accepts the new generation only when the
task's agent-history ledger contains a continuous same-engine `Provider quota reset.` switch chain.
Any other generation, role, engine, agent, card, or recipient-session change fails closed without a
prompt.

## Real Herdr smoke test

Mock tests prove command shape and state behavior, not live wake delivery. Use a harmless delegated
task and a real Codex lead for the final check:

1. From the canonical checkout, identify the intended Codex lead with `herdr --session <session>
   agent get <pane-id>`. Confirm `agent=codex`, note `agent_session.value`, and do not use a blocked
   pane.
2. Create a visible watcher tab in the same session with `herdr --session <session> tab create
   --workspace <workspace-id> --cwd <canonical-harness-path> --label "Codex wake <task-id>"
   --no-focus`. Read the returned root pane id.
3. Start the ordinary process there with `herdr --session <session> pane run <watcher-pane-id>
   "scripts/codex-completion-watch.sh start <task-id> --session <session> --pane <codex-pane-id>"`.
4. Let the harmless specialist settle. Confirm the watcher tab exits, `status` reports `delivered`,
   and the captured Codex conversation receives exactly one bounded completion prompt and begins a
   new turn.
5. Confirm the task metadata generation and recipient `agent_session.value` still match the watcher
   record. If either changed, the expected result is `failed`, not delivery.

Record the real session, pane ids, task id, and observed result. A mock-only run must not be reported
as proof that live wake delivery works.

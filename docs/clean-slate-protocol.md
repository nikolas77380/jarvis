# Clean Slate Protocol

Clean Slate is the harness-native replacement for Jarvis's external `no-mistakes` gate. It keeps
the useful independent review loop, removes repeated cold starts, and uses ordinary processes for
tests, publishing, and CI observation.

## Configure a project

Create `config/projects/<project>.json`, using `config/projects/example.json` as the shape. `checks`
is an ordered list of argument arrays: commands are executed directly, without `eval` or a shell
configuration file. Set `publish` to `false` only for local projects that intentionally have no PR.

Add `**Validation:** strict` or `direct` to the task card. Missing values default to `strict`.

## Run it

```bash
scripts/clean-slate-protocol.sh run <task-id>
scripts/clean-slate-protocol.sh status <task-id>
scripts/clean-slate-protocol.sh status <task-id> --json
scripts/clean-slate-protocol.sh logs <task-id>
```

In strict mode, inspect the review result before choosing a response:

```bash
scripts/clean-slate-protocol.sh respond <task-id> --action fix
scripts/clean-slate-protocol.sh respond <task-id> --action approve
scripts/clean-slate-protocol.sh respond <task-id> --action skip
```

`fix` dispatches the bounded fixer. `approve` and `skip` proceed to deterministic checks. A status
read reconciles completed agent JSON and, while CI is active, refreshes `gh-axi pr checks`.

## Cost and safety model

- One full review; a second review sees only the fixer delta.
- At most two review rounds.
- Reviewer and fixer Herdr identities are reused within a run.
- No LLM agent runs tests, creates the PR, or watches CI.
- Structured results and logs live under the task worktree's `.clean-slate/<task-id>/` directory.
- The protocol stops at `ready`; it never merges.

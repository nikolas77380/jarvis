# Clean Slate Protocol — implementation plan

Replace the external `no-mistakes` dependency with a harness-native validation pipeline. The
pipeline runs against an existing task worktree, uses visible Herdr agents for judgement, executes
project checks deterministically, and stops at a green pull request. It never merges.

## Public contract

```text
scripts/clean-slate-protocol.sh run <task-id>
scripts/clean-slate-protocol.sh status <task-id> [--json]
scripts/clean-slate-protocol.sh respond <task-id> --action fix|approve|skip
scripts/clean-slate-protocol.sh abort <task-id>
scripts/clean-slate-protocol.sh logs <task-id>
```

Task cards declare `**Validation:** strict|direct`; a missing value safely defaults to `strict`.
Project commands live in `config/projects/<project>.json`. State is local and ignored by git.

## States

`preflight -> reviewing -> awaiting-response -> fixing -> verifying -> publishing -> ci -> ready`

`direct` omits review and fix. Operational failures enter `failed`; user cancellation enters
`aborted`. A run is pinned to the implementation HEAD. Review fixes may advance HEAD, and the next
review receives only that delta. Two review rounds are allowed; unresolved findings then require a
human decision.

## Safety boundaries

- One active run per task and one stage agent at a time.
- Existing task agent/worktree metadata is authoritative; no new app worktree is created.
- Agents write structured stage results under `.clean-slate/<run-id>/` in the task worktree.
- Shell commands are JSON array values, never sourced as shell configuration.
- `approve` and `skip` are explicit; ambiguous/product findings are never auto-fixed.
- GitHub operations use `gh-axi`; merge is outside this protocol.

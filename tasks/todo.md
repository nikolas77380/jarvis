# Multi-project review ledger: checkpoint/handoff/review-rounds

- [ ] `review-rounds.sh` resolves the task's project from its id (reuse `task_card`/`card_project`),
      not from `dirname(BASH_SOURCE)`
- [ ] `review-rounds.sh` counts reviewer runs from `agent-history/<task-id>.jsonl`
      (`scripts/agent-review.sh`'s ledger), not from `~/.claude/projects/*/subagents/*.meta.json`
- [ ] `checkpoint.sh` / `handoff.sh` verified working end-to-end for a real task in a real project
- [ ] Test coverage ported from `projects/bridgeks-app/scripts/test/review-rounds.test.sh` +
      `review-rounds.mutants.py`, adapted to the new data sources, added under harness-root `tests/`
- [ ] `RULES.md` documents the fixed behavior (project resolution, ledger source)
- [ ] Decide and document: do per-project `scripts/checkpoint.sh` / `handoff.sh` / `review-rounds.sh`
      copies (e.g. `projects/bridgeks-app/scripts/*`) get retired in favor of the harness-root
      versions, or kept and re-synced? (Out of scope to decide unilaterally — surface it, this task
      does not delete or rewrite anything under `projects/*/scripts/`.)

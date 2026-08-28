# Layered memory

The harness loads knowledge at the narrowest valid scope:

```text
memory/captain.md             explicit user preferences
memory/harness.md             verified cross-project operating rules
memory/projects/<project>.md  facts valid only for one repository
memory/incidents/...          observations awaiting disposition
```

Use `memory-context.sh --project <name>` for normal work. It never loads another project's file and
excludes incidents by default. `--include-incidents` adds open global and selected-project incidents;
`--json` returns the selected source paths without loading their prose.

Record an observation without turning it into policy:

```bash
scripts/memory-record.sh incident bridgeks stale-cache --summary "The check failed after a stale cache."
```

After verification and human review, explicitly promote its Summary:

```bash
scripts/memory-promote.sh bridgeks/stale-cache --scope project --project bridgeks
scripts/memory-promote.sh global/tool-contract --scope harness
scripts/memory-promote.sh global/merge-preference --scope captain
```

Promotion appends the lesson and its source path to the target, then atomically changes the incident
from `open` to `promoted`. It refuses a second promotion. Existing `feedback_*.md` files remain
immutable evidence linked from the concise captain and harness layers.

`session-start.sh --project <name>` renders the selected durable context before decisions, events,
plan cards and fleet state. No token threshold, automatic summarizer, embedding store, or automatic
promotion is involved.

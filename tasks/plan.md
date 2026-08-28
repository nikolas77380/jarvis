# Layered memory — specification

## Objective

Load durable knowledge at the narrowest valid scope: captain preferences, cross-project harness
rules, one selected project's facts, and optional unresolved incidents. Preserve evidence and never
promote an observation into a standing rule automatically.

## Commands

```text
scripts/memory-context.sh [--project <name>] [--include-incidents] [--json]
scripts/memory-record.sh incident <project|global> <slug> --summary <text>
scripts/memory-promote.sh <project|global>/<slug> --scope captain|harness|project [--project <name>]
scripts/session-start.sh [--project <name>]
```

## Storage and invariants

- `memory/captain.md`: explicit user preferences only.
- `memory/harness.md`: verified rules that apply across repositories.
- `memory/projects/<name>.md`: durable facts limited to one project.
- `memory/incidents/<project|global>/<slug>.md`: observations with `open|promoted|dismissed` status.
- Existing `feedback_*.md` files remain immutable evidence and are indexed from the new layers.
- Context excludes incidents by default and never loads another project's memory.
- Promotion is explicit, append-only at the target, records its source path, and atomically marks the
  incident promoted. A promoted incident cannot be promoted twice.

## Testing and boundaries

Shell integration tests cover project isolation, default selection, incident creation, explicit
promotion, duplicate refusal, and session-start project routing. No vector database, embeddings,
automatic summarization, token threshold, or automatic promotion is introduced.

## Implementation order

1. Layer files and project template.
2. Context selector.
3. Incident record and promotion.
4. Session-start routing and legacy evidence index.
5. Documentation and full regression.

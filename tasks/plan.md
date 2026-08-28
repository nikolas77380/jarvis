# Durable inbox and decisions — specification

## Objective

Persist actionable task transitions and captain decisions across sessions without a daemon or an
LLM poller. Session start must reconstruct attention from append-only local records.

## Commands

```text
scripts/inbox.sh list [--json]
scripts/inbox.sh acknowledge <event-id>
scripts/inbox.sh drain
scripts/decisions.sh open <task-id> --key <key> --question <text>
scripts/decisions.sh list [--json]
scripts/decisions.sh resolve <key> --answer <text>
scripts/events-poll.sh
```

## Interfaces

- `.harness-state/events.jsonl` is append-only `harness-event.v1`; acknowledgements are a separate
  append-only ledger. Event IDs are stable hashes of task, type, and observed generation.
- `.harness-state/decisions.jsonl` is an append-only opened/resolved ledger keyed by a caller-owned
  stable key. Reopening an unresolved key is idempotent; resolving an absent/already resolved key
  refuses.
- Poll compares `fleet-snapshot.v1` with the previous durable snapshot and emits only actionable
  transitions. First observation emits actionable current states but not routine idle/working state.
- Session start polls, then renders open decisions, unread events, and fleet. No network access and
  no automatic repair occur.

## Testing and boundaries

Shell integration tests cover append validity, deduplication, acknowledgement without event
rewrites, decision folding, transition deduplication, and session recovery. All writes use global
state locks and atomic snapshot replacement. Never delete event/decision history or infer a
decision resolution from task prose.

## Implementation order

1. Event and acknowledgement ledger.
2. Keyed decision ledger.
3. Fleet transition poll and automatic decision findings.
4. Session-start presentation, documentation, full regression.

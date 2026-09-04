# Durable inbox and decisions

The harness records actionable state transitions without a daemon in
`.harness-state/events.jsonl`. Acknowledgements are appended separately, so reading or draining the
inbox never rewrites history.

```bash
scripts/events-poll.sh
scripts/inbox.sh list
scripts/inbox.sh list --json
scripts/inbox.sh acknowledge <event-id>
scripts/inbox.sh drain
```

Poll compares the local fleet snapshot with its previous atomic snapshot. It emits transitions for
agent completion/block/missing state, review response, pipeline failure, CI readiness, and task
archival. Stable event IDs deduplicate repeated polls.

Captain decisions use an independent append-only ledger:

```bash
scripts/decisions.sh open <task-id> --key <key> --question "..."
scripts/decisions.sh list
scripts/decisions.sh resolve <key> --answer "..."
```

The latest opened/resolved record for each key determines whether it is open. Clean Slate findings
classified `needs-decision` are ingested automatically using `<task>-<finding-id>` as the stable key.
`session-start.sh` polls once and then shows open decisions, unread events, plan cards, and fleet.

Acknowledging an `agent-done` event is also what makes its specialist's settled Herdr tab eligible for
closure: `scripts/agent-cleanup.sh <event-id>` refuses to close anything until that exact event id is
present in `event-acks.jsonl`, then closes only if the task's current runtime metadata still matches
the identity the event recorded. Closing is a deliberate call the lead makes for a generation it will
not hand to another agent — nothing invokes it automatically. See "Behaviour" in
`docs/herdr-runtime.md` for the full ordering and safety contract.

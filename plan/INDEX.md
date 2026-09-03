# Plan index

One line per task. **Read this file first and open only the cards you need** — that is the whole
point of the split. Ordering constraints and cross-task dependencies live HERE, not inside the cards,
because a card read on its own cannot tell you it must wait for another.

Status: `open` · `in-progress` · `in-review` · `blocked` · `needs-decision` · `done`
Owner: which agent, `user` when the decision is theirs, `lead` for the orchestrator session.

| id                                                               | task                       | status      | owner          | depends on      | note                                 |
| ---------------------------------------------------------------- | -------------------------- | ----------- | -------------- | --------------- | ------------------------------------ |
| [260831-2017-001](260831-2017-001-root-project-adapter.md)       | root project adapter       | done        | lead           | —               | PR #2 merged as 7bb4828              |
| [260902-1204-001](260902-1204-001-macos-bootstrap.md)            | macos bootstrap            | in-progress | shell-engineer | 260831-2017-001 | PR #3 · fixing round 1               |
| [260902-1411-001](260902-1411-001-global-js-agent-roles.md)      | global js agent roles      | in-review   | deputy         | —               | PR #4 · five adapted global JS roles |
| [260902-1545-001](260902-1545-001-capability-aware-design-qa.md) | capability aware design qa | done        | lead           | —               | PR #5 merged as b7f3706               |

## Ordering that is not obvious

- **T0x before T0y**, and the reason. Only put entries here that a reader would get wrong by
  default — an obvious dependency does not need a line.

## What is already done (do not re-plan it)

Short list, with pointers to `OVERVIEW.md` for the running log.

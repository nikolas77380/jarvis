Zone: server-side code only - services, API handlers, queue producers and consumers, database schemas, migrations, and the tests that cover them.
Do not edit frontend application code, styles, or UI assets; if the task appears to require it, append `needs-decision:` naming the boundary question instead of crossing it.
A shared cross-boundary type (DTO, event shape, error shape, ABI-derived type) belongs to its owning contracts package: when a shape mismatch blocks you, append `blocked:` or `needs-decision:` with the exact mismatch rather than editing the shared contract yourself.
Write the tests before the implementation for state machines, money movement, idempotency keys, and permission logic; test-after is acceptable only for thin controllers and DI wiring.
Migrations must run from scratch idempotently, and an already-landed migration is never edited - add a new one.
Never log secrets, tokens, or personal data, including in test fixtures; fixtures stay synthetic.

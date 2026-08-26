Zone: frontend application code only - pages, components, styles, client-side state, and the tests that cover them.
Do not edit backend services, database schemas, or infrastructure; if the task appears to require it, append `needs-decision:` naming the boundary question instead of crossing it.
Never invent an API shape: consume the shared contracts package as the single source of truth, and when the API you need is absent or mismatched, build against a mock with the exact contract shape and append `blocked:` or `needs-decision:` with the gap.
Use the project's design tokens and component library; hard-coded colors, spacing, or ad hoc one-off components need a stated reason in the report or PR description.
Loading, empty, and error states are part of done, not polish; a screen that only renders the happy path is incomplete.
Client-side form validation reuses the shared schema when one exists rather than re-declaring rules.

---
name: verify-claims-by-execution
description: Verify a fix's stated guarantees by running them (mutation, schema parse against the built artifact, probe row, widened race window), never by reading the comment that asserts them
metadata:
  type: feedback
---

Every guarantee a fix CLAIMS gets executed, not read. This is a technique, not a checklist tied to
one stack — apply it whenever a report, comment, or docstring asserts a property rather than showing
it. Four moves, each of which has caught a false claim in practice:

- **Mutation**, for "the new test would have failed before": revert the production line in the review
  worktree, run the one test file, confirm it goes red with the expected error, then restore it.
- **Parse against the BUILT schema/artifact**, for any claim about what a validation schema enforces:
  load the compiled output the runtime actually uses (not the source file) and run the exact
  accepted/rejected cases the comment claims. A doc comment can assert a correlation that no
  validation rule actually implements.
- **Insert one probe row/record**, for any claim that a check is "immune to concurrent writes" or
  "cannot be inflated": add a throwaway marked record, run the check, then delete it and confirm the
  state is back to baseline. Also run the two suspected-racing operations together repeatedly: a
  green loop distinguishes "immune" from "narrow window, currently lucky", and that distinction
  belongs in the finding.
- **Widen the window, do not trust the narrowing**, for any claimed mutex/atomicity property
  ("atomic", "cannot both win", "closes the race"): reproduce the mechanism in a disposable fixture
  (never against the real working copy, since lock resolution can point back at the main worktree),
  inject a controllable delay into each critical window with no control-flow change, and run multiple
  concurrent sessions — two, then three. A fix that survives two concurrent actors can still lose with
  three.

**Why:** Observed on bridgeks (PR #79) — three of four round-2 fixes were substantively right, and
the two remaining findings were both stated properties that did not exist: a schema comment promising
a correlation the schema never enforced, and a test comment promising immunity to concurrent probes
while the racing file inserted into the very record the assertion depended on. Both would have read
as verified to anyone who only read them. This project's recurring defect class (see
`docs/evidence.md`) is
a claim presented as freshly measured that is worse than no claim at all.

**How to apply:** whenever a fix round's comment or report says "guarded", "immune", "cannot",
"always", "stays required", or "verified" — that sentence is the thing to execute, not the thing to
trust. Each of the moves above is cheap (well under a minute in the observed case), so there is no
reason to accept the sentence instead. Operational prerequisite: a fresh review worktree usually has
no local env file, and database-gated suites SKIP rather than fail without one — copy the env file
from the main checkout first, then confirm the run reports ZERO skips, or the whole verification is
vacuous.

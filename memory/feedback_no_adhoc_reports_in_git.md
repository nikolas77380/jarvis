---
name: no-adhoc-reports-in-git
description: Ad-hoc measurement reports (cost/token stats over local transcripts) stay local, never committed; the decision doc carries the numbers and the method
metadata:
  type: feedback
---

Do not commit ad-hoc measurement reports (session-cost statistics computed over local transcripts,
or any similar one-off analysis). Observed on bridgeks, 2026-08-26: the user said "we definitely
don't commit that" when the lead proposed committing one as the source for a rules-file change.

**Why:** the number and the method belong in the project's dated decision record (its
`docs/decisions/` equivalent — see `docs/evidence.md`), not in a raw per-session dump; a `reports/`
directory is for delegated task runs tied to a card, not for ad-hoc measurement.

**How to apply:** when a measurement drives a rule change, write the figures, the date, the script
and the data source into the dated decision entry, and leave the deputy's report file untracked.

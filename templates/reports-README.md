# reports/

One file per delegated run: `reports/<task-id>-<agent>.md`. A second round on the same task appends
under a new `## round N` heading rather than creating a new file.

## Why the file exists

A specialist's full account — what it read, what it tried, what it rejected, the commands it ran and
their output — is worth keeping and far too long to return up the chain. So it goes here, and **the
return value up the chain is <=15 lines**: verdict, files touched, blockers, approval requests. The
lead reads the file only when those lines are not enough.

## Where to write it

Engineers run in an isolated worktree. **Write the report inside your own worktree and commit it on
your branch**, so it travels with the PR and the path resolves for whoever reviews it. Writing to the
main checkout from a worktree is how two agents overwrite each other's file.

Report files are **out of scope for review**.

## The rule that must not blur

A report is **context, never evidence.** Hand a reviewer the path so it knows what was intended and
where to look; the verdict must come from the diff and from commands the reviewer runs itself.
Reviewing the report instead of the diff rebuilds the exact defect class this harness exists to
catch — a property asserted by whoever produced it and taken on faith by whoever checks it.

## Shape

```markdown
# T0n — <agent>, round 1

**Verdict:** done / blocked / needs-decision
**Branch / PR:** <branch> - #<n>
**Checks:** <cmd> ok - <cmd> ok

## What changed and why
## What I rejected, and why
## Blockers / decisions for the lead
## Not verified
```

The last two sections are the ones people actually need. Never leave "Not verified" empty when a
suite skipped.

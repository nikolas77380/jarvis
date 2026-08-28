# Layered harness memory

Normal context loads `captain.md`, `harness.md`, and at most one `projects/<project>.md`. Temporary
observations live under `incidents/` and are excluded unless explicitly requested. Promotion into a
durable layer is always explicit and records provenance.

The older `feedback_*.md` and `project_*.md` files below remain detailed evidence. The concise upper
layers link to them instead of duplicating their incident history.

```bash
scripts/memory-context.sh --project <project>
scripts/memory-context.sh --project <project> --include-incidents
scripts/memory-record.sh incident <project|global> <slug> --summary "..."
scripts/memory-promote.sh <project|global>/<slug> --scope harness
```

## Legacy portable memory

This directory holds agent-memory entries that are **pipeline lessons**, not project facts — the
subset of a memory store that survives a move to a different codebase because it is about how the
agents work together, not about what any one repo contains.

## Why these are portable and the rest of a memory store is not

A typical agent-memory store mixes several things: who the user is, what a specific module does, what
a specific PR broke, and how the pipeline itself misbehaves under specific conditions (a locked
worktree treated as dead, a report that got committed when it shouldn't have, a tool named in a brief
that doesn't exist). The first three are tied to one project and one team; reading them into a new
project would import stale or simply wrong assumptions. The last kind is different: it is a lesson
about the mechanics of planning, delegating, and verifying with these agents, and that mechanic is the
same regardless of which repository or stack sits underneath it.

Every file here was filtered for that property before being ported: incidents are kept as evidence
(dates, PR numbers, measured costs — labelled as observed on the source project) because a rule
without a reason gets "optimised" away by the next person who finds it inconvenient, but anything tied
to that project's own module architecture, CI state, or domain decisions was left behind.

## What's here

- `feedback_*.md` — corrections or confirmations about HOW to run the pipeline: when to ask before
  delegating, when a worktree is live vs dead, when to preview instead of merge, when NOT to commit a
  report.
- `project_*.md` — a fact about the AGENT'S ENVIRONMENT (not the target project's code) that future
  sessions need, ported because the underlying risk — a brief naming a tool that was never confirmed
  to exist — recurs in any pipeline, not just the one it was first observed on.

`[[wiki-links]]` between files are kept even where the link target was not ported (e.g. a link to a
project-specific card or an unported memory). A dangling link marks something worth writing later for
the target project; it is not an error.

## How to install these into a target project

1. Copy the files you want into the target project's own agent-memory store, under the persona
   directory that will use them (an orchestrator-equivalent lead persona for the `feedback_*` files
   here, the logic-tier reviewer persona for the `nestjs-reviewer`-sourced ones — rename the files to
   match your project's persona names if useful, the `name:` field in the frontmatter is what matters,
   not the filename).
2. Add one line per file to that persona's `MEMORY.md` index, in the same one-line-per-entry format
   the rest of that index already uses: `- [Title](file.md) — one-line hook`.
3. Resolve or intentionally leave dangling any `[[wiki-links]]` inside the copied files — a link to a
   memory that doesn't exist yet in the target project is fine, a link to one that should exist but
   was renamed is not.
4. Re-read each file once installed and swap out anything still describing the source project by name
   (a stray "bridgeks" that should read as your project) — the ones here were already written to keep
   project-specific detail behind an "Observed on bridgeks" label rather than in the operative
   sentence, but check anyway.

Do not port a memory file wholesale without reading it first: a lesson that looks generic can still
carry an assumption specific to the source project's directory layout or tooling names.

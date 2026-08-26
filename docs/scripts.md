# The bin/ toolbelt

The Jarvis drives these; interactive entrypoints work by hand too, while `*-lib.sh` files are sourced helpers.
Each row is one purpose clause only: the script's own header comment is the authoritative description of its behavior, flags, and contracts, so read the header before first use.
If you have changed away from the jarvis home in an interactive shell, invoke these scripts by absolute path through the repo's `bin/` directory; the scripts self-locate internally after they start.
The shared no-mistakes gate refusal for fleet lifecycle entrypoints is summarized in [architecture.md](architecture.md#no-mistakes-gate-authority-boundary), while `docs/sessionstart-nudge.md` covers the silent session-open hook use; `dj-gate-refuse-lib.sh`'s header owns its exact contract.

| Script                   | Purpose                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------ |
| `dj-session-start.sh`    | Compose lock, bootstrap, and wake drain into the single ordered session-start digest |
| `dj-sessionstart-nudge.sh` | Print the native session-start hook nudge when the primary has not already run the digest |
| `dj-sessionstart-run.sh` | Route a native session-open hook to the full digest, a context re-emit, or the nudge |
| `dj-operational-input.sh` | Construct and parse the canonical cross-language operational-input protocol |
| `dj-bootstrap.sh`        | Detect toolchain and fleet problems, run the locked session-start sweeps, and install approved tools |
| `dj-startup-network.sh`  | Run session start's network checks off its blocking path, retaining every report while waking only for actionable results |
| `dj-fleet-sync.sh`       | Refresh project clones with safe fast-forwards, self-heals, `STUCK:` reports, branch pruning, and bounded recovery from an orphaned `.git/packed-refs.lock` |
| `dj-fleet-snapshot.sh`   | Print the read-only structured fleet snapshot JSON (schema `dj-fleet-snapshot.v1`)   |
| `dj-fleet-view.sh`       | Render the fleet snapshot as a human Markdown view                                   |
| `dj-bearings-snapshot.sh` | Project the fleet snapshot to the compact TOON bearings view; local-only unless `--include-prs` |
| `dj-bearings-board.sh`   | Build and arm the stable interactive `/bearings edith` fleet board                  |
| `dj-update.sh`           | Fast-forward-only self-update of jarvis and local or remote secondmate homes       |
| `dj-on.sh`               | Execute one tracked Jarvis command in a configured remote secondmate home, using its job worker except for the doctor bootstrap |
| `dj-remote-job-lib.sh`   | Shared bounded remote job queue, worker readiness, LaunchAgent contract, and filesystem-composed PATH |
| `dj-remote-job-worker.sh` | Long-lived remote queue worker for tracked `dj-*.sh` commands in the account runtime |
| `dj-remote-job-reap-orphans.sh` | Stop remote job workers left running by a pruned code root, never one whose checkout still exists |
| `dj-remote-doctor.sh`    | Check, and with `--fix` repair, one remote account's second-mate readiness (remote job worker, Herdr, Aqua launch agents, PATH, and required tools) |
| `dj-backlog-handoff.sh`  | Move queued backlog items into a secondmate home and durably wake its recorded receiver |
| `dj-backlog-receive.sh`  | Idempotently ingest one confined remote handoff outbox through tasks-axi             |
| `dj-captain-hold.sh`     | Hold tasks for the captain, record the captain's answers, gate investigation completion, and report record divergence between the status log and the backlog |
| `dj-decision-hold.sh`    | One-release compatibility shim mapping the retired decision commands onto dj-captain-hold.sh |
| `dj-brief.sh`            | Scaffold ship (explicit `--mode`), scout, secondmate-charter, and Herdr-lab briefs   |
| `dj-herdr-lab.sh`        | Provision and guardedly operate an isolated, never-default Herdr lab session         |
| `dj-install-herdr.sh`    | Install CI's exact-version Herdr pin with official asset URL, SHA-256, and protocol checks |
| `dj-install-treehouse.sh`| Install CI's exact-version Treehouse pin for real-Herdr E2E that needs spawn worktrees |
| `dj-herdr-ci-cleanup.sh` | Snapshot and tear down only job-owned `dj-lab-*` sessions in the Herdr CI lane       |
| `dj-test-run.sh`         | Behavior-test runner: selection, portable lanes, proven-isolated `--jobs`, coverage guard, timing/JSON |
| `dj-test-isolation-proof.sh` | Concurrent isolation proof and proven-isolated candidate set owner |
| `dj-ensure-agents-md.sh` | Ensure a project's real `AGENTS.md`, its `CLAUDE.md` `@AGENTS.md` pointer, and the canonical self-governance section |
| `dj-guard.sh`            | Warn on primary-checkout tangles, pending queued wakes, and unhealthy supervision    |
| `dj-primary-scope-lib.sh` | Shared marker-or-plain-checkout primary-home predicate for tracked hooks             |
| `dj-session-lock-lib.sh` | Shared session-lock harness identity (ancestry walk and holder liveness) for dj-lock.sh and the Claude Stop auto-arm |
| `dj-claude-stop-autoarm.sh` | Claude Stop `asyncRewake` hook owning tokenless watcher continuity with single-flight exit-2 rewake (docs/watcher-continuity.md) |
| `dj-turnend-guard.sh`    | Shared primary turn-end guard predicate so no turn ends blind (docs/turnend-guard.md) |
| `dj-turnend-guard-grok.sh` | Grok Stop-hook adapter for the primary turn-end guard                              |
| `dj-kimi-turnend-hook.sh` | Surgically install or remove Kimi's guarded global crew turn-end hook                |
| `dj-arm-pretool-check.sh` | Stable PreToolUse transport for the watcher-arm command policy (docs/arm-pretool-check.md) |
| `dj-arm-command-policy.mjs` | Semantic owner of the watcher-arm PreToolUse policy (docs/arm-pretool-check.md)   |
| `dj-subagent-pretool-check.sh` | Primary-home delegation-shape PreToolUse guard (docs/subagent-guard.md) |
| `dj-supervision-instructions.sh` | Render the session-start primary-harness supervision block or the one-line repair instruction |
| `dj-home-seed.sh`        | Transactionally provision a local secondmate home and maintain `data/secondmates.md` |
| `dj-remote-home-seed.sh` | Register and provision a whole secondmate home on an SSH-reachable host              |
| `dj-remote-readiness-lib.sh` | Shared remote second-mate readiness gate: check and, when needed, repair then re-check through `dj-remote-doctor.sh` |
| [`dj-project-origin-lib.sh`](../bin/dj-project-origin-lib.sh) | Accepted origin-form owner shared by both remote provisioning boundaries |
| `dj-spawn.sh`            | Spawn crewmates, scouts, `id=repo` batches, and secondmates on the resolved harness and runtime backend |
| `dj-backend.sh`          | Runtime-backend selection, meta helpers, selector resolution, and operation dispatch |
| `dj-backend-hometag-lib.sh` | Shared per-installation home-tag derivation for zellij tab and cmux workspace titles |
| `dj-composer-lib.sh`     | Single fleet-wide owner of composer shapes, capability-aware screen classification, and verdicts |
| `backends/tmux.sh`       | Verified tmux session-provider adapter                                               |
| `backends/herdr.sh`      | Experimental herdr session-provider adapter                                          |
| `backends/zellij.sh`     | Experimental zellij session-provider adapter                                         |
| `backends/orca.sh`       | Experimental Orca backend adapter owning both worktree and terminal                  |
| `backends/cmux.sh`       | Experimental cmux session-provider adapter                                           |
| `dj-config-push.sh`      | Push declared inherited local material to live local or remote secondmates and send the placement-specific config reread when changed |
| `dj-project-mode.sh`     | Resolve a project's registered delivery posture from `data/projects.md` for fleet sync and home seeding |
| `dj-merge-local.sh`      | Fast-forward a `local-only` project's local default branch after approval            |
| `dj-review-diff.sh`      | Review a crewmate branch or resolved PR head against the authoritative base          |
| `dj-marker-lib.sh`       | Compatibility entry point for the from-jarvis carrier owned by `dj-operational-input.sh` |
| `dj-task-inbox-lib.sh`   | Single owner of durable steering-inbox records, acknowledgement, doorbells, and the delivery-attempt ladder |
| `dj-pending-reply-lib.sh` | Parent-owned secondmate pending-reply expectations, recovery, and keyed escalation lifecycle |
| `dj-secondmate-report.sh` | Optional helper to append a correlated parent status or document-pointer report       |
| `dj-procevent-remote-reply.sh` | Relay the remote-secondmate status stream through non-destructive process-event deltas |
| `dj-procevent-when.sh`   | Fire a trust-bound deterministic action at most once when its registered condition holds, then wake with the outcome |
| `dj-gate-refuse-lib.sh`  | Shared no-mistakes gate-context refusal for fleet lifecycle entrypoints               |
| `dj-watch-arm.sh`        | Verified home-scoped watcher arm wrapper with loud cycle endings and bounded lifecycle ledger |
| `dj-watch-checkpoint.sh` | Run one bounded foreground watcher checkpoint for Codex-style supervision            |
| `dj-watch.sh`            | Singleton-safe watcher: absorb benign wakes, detect stalled local-secondmate wake queues, and exit on actionable ones |
| `dj-inactive-reconcile.sh` | Reconcile long-inactive direct crewmate terminal outcomes without forge access |
| `dj-afk-start.sh`        | Run the common sourceable away-mode daemon entry in the foreground                      |
| `dj-afk-launch.sh`       | Own away-mode entry, exit, rollback, and any backend terminal lifecycle                 |
| `dj-afk-return.sh`       | Own deterministic return shutdown, catch-up evidence, and the jarvis-actionable blocker gate |
| `dj-supervisor-target-lib.sh` | Resolve the shared supervisor target and backend for the daemon and launcher       |
| `dj-supervise-daemon.sh` | Presence-gated away-mode sub-supervisor: self-handle routine wakes, guard injection by the detected primary harness, escalate batched digests, alert on failed delivery |
| `dj-crew-state.sh`       | Print one deterministic current-state line for a crew                                |
| `dj-nm-run-lib.sh`       | Shared branch-and-code-identity attribution for no-mistakes runs                    |
| `dj-tangle-lib.sh`       | Shared default-branch resolution and primary-checkout tangle classification          |
| `dj-timeout-lib.sh`      | Single owner of hard-bounded command execution and its fallback watchdog |
| `dj-timing-lib.sh`       | Single owner of the deferred network stage's per-step elapsed-time records, inert unless a run asks for them |
| `dj-supervision-lib.sh`  | Shared in-flight-work-without-fresh-watcher-beacon predicate                         |
| `dj-ff-lib.sh`           | Shared guarded fast-forward helper for origin pulls and local secondmate syncs       |
| `dj-lock-lib.sh`         | Shared "is this git lock provably abandoned?" proof used by teardown and fleet-sync   |
| `dj-config-inherit-lib.sh` | Shared primary-to-secondmate inherited local-material propagation and config-reread delivery |
| `dj-tasks-axi-lib.sh`    | Shared backlog-backend selector and `tasks-axi` compatibility probe                  |
| `dj-quota-axi-lib.sh`    | Shared `quota-axi` compatibility floor for the bootstrap diagnostic                  |
| `dj-vendor-auth-probe.sh`| Run one hard-bounded, non-destructive authentication probe of a named vendor CLI and report the fact |
| `dj-wake-drain.sh`       | Present and acknowledge the current actor's claimed wake rows alongside status, decision, divergence, recovery, and supervision checks |
| `dj-wake-grant.sh`       | Serialize Pi supervision-branch wake-row claim activation, publication, release, and deactivation |
| `dj-wake-lib.sh`         | Shared durable wake queue, recovery generations, portable locks, and watcher identity/health helpers |
| `dj-classify-lib.sh`     | Shared wake-classification vocabulary, durable keyed-decision folds and scans, and unread informational status-line selection |
| `dj-send.sh`             | Steer a task via a durable inbox record plus doorbell, or send a supported key or typed harness invocation through the recorded backend |
| `dj-branch-prompt.sh`    | Emit the Pi supervision branch's byte-stable system prompt ([pi-supervision-branch.md](pi-supervision-branch.md)) |
| `dj-branch-outcome.sh`   | Own the supervision branch's append-only outcome store, read cursor, and session-start replay |
| `dj-lease.sh`            | Claim, release, inspect, and sweep per-task supervision leases                       |
| `dj-lease-lib.sh`        | One owner of the supervision lease contract and the main-only role-partition guards  |
| `dj-control.sh`          | Agent lifecycle control plane: allowlisted `interrupt`, `exit`, and transactional `relaunch` verbs for an exact task id ([agent-control.md](agent-control.md)) |
| `dj-control-lib.sh`      | One executable owner of the control-plane verb allowlist, per-harness interrupt/exit mechanics, and per-backend capability |
| `dj-busy-lib.sh`         | Single owner of the semantic busy-state contract: verdicts, source attribution, and per-harness sources |
| `dj-busy-event.sh`       | The only writer of a task's semantic busy-state record; arms an incarnation and applies lifecycle events |
| `dj-tmux-lib.sh`         | Shared tmux pane primitives for composer capture, verified submit, and the submit-time busy check |
| `dj-peek.sh`             | Print a bounded tail of a crewmate endpoint                                          |
| `dj-check-register.sh`   | Bind an intentional custom watcher check to its current bytes                       |
| `dj-check-lib.sh`        | Validate custom-check registrations and prepare private execution snapshots          |
| `dj-tool-update-check.sh` | Report watched tooling with an update available, and updates installed but left inert by PATH order |
| `dj-pr-lib.sh`           | Own canonical task and PR validation plus private atomic PR-poll publication, merge-notification identity, and retirement |
| `dj-pr-poll.sh`          | Provide the byte-static watcher program for validated PR/MR-poll sidecars           |
| `dj-pr-check-migrate.sh` | Quarantine older task polls without execution and rebuild only canonical polls       |
| `dj-pr-check.sh`         | Record validated `pr=` and `pr_head=` values, then atomically arm a static merge poll |
| `dj-pr-merge.sh`         | Record PR metadata, then merge a task's canonical full GitHub or GitLab URL          |
| `dj-promote.sh`          | Promote a scout task in place to a protected ship task with an explicit delivery mode |
| `dj-teardown.sh`         | Fail-closed teardown: return landed ship worktrees, require completed scout deliverables, retire secondmate homes |
| `dj-harness.sh`          | Detect the running harness and resolve crew or secondmate harness, model, and effort |
| `dj-lock.sh`             | Per-home jarvis session lock                                                      |
| `dj-x-lib.sh`            | Shared Relay config, relay, and reply-threading helpers                              |
| `dj-x-poll.sh`           | One bounded Relay poll: stash newly offered mentions and emit their once-only wake   |
| `dj-x-reply.sh`          | Post or dry-run preview a composed Relay reply or follow-up                          |
| `dj-x-dismiss.sh`        | Dismiss a skipped Relay mention at the relay without replying                        |
| `dj-x-link.sh`           | Link a spawned task to its originating Relay mention in task meta                    |
| `dj-x-followup.sh`       | Detect, post, and cap completion follow-ups for a Relay-linked task                  |
| `dj-public-followup-lib.sh` | Shared Relay gate, open-loop registry state, expiry classification, locking, and private transport paths |
| `dj-public-followup.sh`  | Reconcile and deliver typed public commitments, then rechain or explicitly retire their retained loops |
| `dj-public-followup-emit.sh` | Report one typed terminal work result into the home that owes the public reply    |
| `dj-inbox.sh`            | The captain's out-of-band capture surface: queue a note, dictate one, read status, ask a side question |
| `dj-voice-relay.py`      | Hold the spoken conversation on this host, answer from the records, and hand real work to `dj-inbox.sh` ([voice-relay.md](voice-relay.md)) |
| `dj-voice-client.py`     | The laptop end of the spoken interface: capture, playback, and turn timing over SSH; audio devices unverified |
| `dj_voice_frame.py`      | The wire format both machines share, copied to the laptop beside the client          |
| `dj_voice_records.py`    | What a spoken answer may read, and the handover that queues real work                |

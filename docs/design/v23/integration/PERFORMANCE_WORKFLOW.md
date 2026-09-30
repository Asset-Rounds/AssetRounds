# Performance workflow — owner approved 2026-09-30

Finish the verified V23-on-S10 merge quickly by advancing its independent blockers together. [AGENTS.md](../../../../AGENTS.md) is binding. Every helper uses GPT-6.1 Sol with `xhigh` reasoning. The ceiling is ten active helpers plus root, subject to actual tool capacity, usage limits and useful work. Full V23 scope, S10 quality, independent review, owner review and every gate remain required.

## One queue and clear ownership

[ACTIVE_BRIEF.md](ACTIVE_BRIEF.md) holds the current blocker queue and next actions; [VERIFICATION_DUE.md](VERIFICATION_DUE.md) holds obligations. Do not create a competing acceptance ledger. Each lane has one author, a separate reviewer when required, an exact source head and an explicit handoff. Root records status and dependencies in the existing records.

Start with these independent lanes, updating their status in ACTIVE_BRIEF as work advances:

| Lane | Bounded outcome | Execution ownership |
| --- | --- | --- |
| App-access prerequisite | Identify the actual failing comparison, fix its proven cause, verify affected behavior | Root owns Xcode and native runs; helpers prepare disjoint source changes and review |
| Cold shared-build qualification | Complete authenticated payload retention, safe extraction, no-rebuild verification and per-partition evidence | One tooling author; disjoint test author if assigned; independent reviewer |
| Remaining unit scaffolds | Replace unresolved scaffolds with real frozen-design behavior coverage and expose missing implementation | One author per disjoint test family; independent review of expectation changes |
| Phase evidence and owner review | Prepare the critical-state checklist and exact evidence links after prerequisites are ready | Reports-only support; root dispatches; the owner supplies genuine human review |

Use all useful ready lanes instead of serializing unrelated work. Keep a reviewer available for completed candidates. Additional helpers take a distinct ready question; an empty slot is not a reason to invent work. Fix prerequisites before spending hosted capacity on dependent UI runs.

## Assignment contract

Every assignment states:

1. The question, required outcome and dependency that it unblocks.
2. Exact head, authoritative source/evidence paths and relevant previous handoff.
3. Owned files in a root-created worktree, or a clearly read-only scope.
4. Expected deliverable: patch, review or compact report with exact source bindings.
5. Required verification, preservation boundaries and escalation conditions.

Tell authors they share the codebase and must preserve others' work. Reuse a relevant helper with follow-up activation before spawning another. Read its bounded handoff rather than repeating the investigation. Preserve historical model attribution and interrupted work. A reviewer never authors its approved change; corrections return to the same reviewer.

## Coordinate the assisting chat

The owner-authorized assisting chat is `01a0f2f6-76ae-7396-b9fb-9f07a07a10c1` on host `durable`. Root sends exact questions, file ownership and source heads, and receives compact progress snapshots and handoffs. Its helpers remain reports-only unless root explicitly assigns isolated patch ownership. Confirm that no other helper owns those files before assigning a patch.

This root alone imports patches, operates Git, dispatches hosted work, runs Xcode/simulators, collects originals and performs storage effects. The assisting chat must not start duplicate builds, collectors, uploads or cleanup. Coordinate active helper counts across chats and honor each tool's capacity. Reconcile any unexpected head or source movement before an effect.

## Keep verification moving

- Freeze each coherent candidate while it is being verified. Prepare subsequent changes in separate worktrees.
- Compile changed Swift first, then run the affected development tests. Run the required CI suites for each changed CI candidate.
- Overlap isolated source work, read-only review and fixture preparation with root's build/test stream. Never mutate source or Products held by a running test or inspection.
- Review the relevant delta and its coupling; reuse exact applicable evidence without extending its scope. Recheck genuine current inputs and authorization at each required boundary.
- Group failures only when a shared cause is proved. One bounded correction and affected verification cycle should address that family.
- Run a deliberate hosted development sweep after meaningful stabilization. Freeze a separate candidate for all required same-head gates. Development results never become gate evidence.
- Do not repeat unchanged full suites or duplicate inventories. Repeat checks when changed inputs, failures or unresolved coupling justify them; mandatory checks and cold qualification remain intact.

## Use the Mac according to measurements

Root checks available disk, memory pressure, CPU and live native jobs before expensive work. On this 16 GB Mac, choose compiler/test worker counts from those observations; six compiler workers have worked for the current recipe. Adjust when measurements warrant it. Helper inference is remote and does not require filling local RAM.

Keep one root-controlled native/build stream for shared Products. Use independent output directories for any permitted parallel work. Preserve the existing admission floors, pressure checks, holder checks and all watchdogs; this document cannot lower them. Avoid paging and disk exhaustion, which slow builds and risk incomplete artifacts.

Storage work yields to verification while space is sufficient. Archive only an approved, independently checked selection. Delete local copies only after verified remote recovery and dependency checks. Preserve current/future artifacts, source, drafts, Products, modules, manifests and ledgers. Restore individual Dropbox artifacts by immutable ID/revision and verify their recorded hashes when needed; do not download the whole archive by default.

## Handoffs and completion

Each lane's handoff gives exact files/head, completed checks, unresolved failures and the next executable step. Record measured elapsed times when they identify a bottleneck. Keep ACTIVE_BRIEF at 60 lines or fewer and fold record changes into the next real checkpoint.

Root reports meaningful progress periodically and keeps the owner informed of blockers. A lane is complete only when its required implementation, review and verification are complete. Phase 1 is complete only after its five gates and exact-main verification; release still requires the full V23 scope and owner decisions.

# Expansion into the existing AssetRounds app

Current navigation checkpoint, 2026-09-19. [CURRENT_INTEGRATION](CURRENT_INTEGRATION.md) controls scope and acceptance; [VERIFICATION_DUE](VERIFICATION_DUE.md) retains detailed obligations. Historical S10 is the accepted base, not a new workstream.

## Destination and present state

- `main` and `phase/s10-brand-refresh` both remain at accepted S10 `b1d04ae5e684aa9c6807af655089efa1df8a7ed6`.
- Work is on `codex/v23-s10-integration-20260910`, a descendant of that base. Current committed head is `6d138e3be14499900bbc67f8e581474f0e9e2f34`.
- The branch has one `FieldEvidenceApp.xcodeproj`, one shared `FieldEvidenceApp` scheme and the existing app architecture. The remaining problem is completing and verifying its production integration, not combining two app projects.
- Native compilation passes at `6d138e3` (original35452536926, zero compiler errors). Check/no-issue still exceeds900 seconds: parent/two-photo preparation takes about640 seconds and the interrupted-target phase begins at743 seconds. No runtime pass is claimed; the diagnostic narrows the expensive work but does not justify removing validation.
- 49 protected local drafts remain preserved; their presence does not mean they are reconciled, committed or accepted.

## Work required before main advances

| Workstream | What remains | Completion evidence |
| --- | --- | --- |
| Current native blocker | Use the phase diagnostic to locate the unfinished parent-finalization operation, then fix its demonstrated cause in a compatible batch. | Exact-head successful compilation and the original functional journey, preserving faults, assertions, protection evidence and budgets. |
| Production adoption | Finish C36 destination/restore correspondence and real receipt joins; child/finalizer recovery; Work/Round field, scene, focus and resume flows; lifecycle/codec/backup registration. Resolution and confirmed discard already have production-service/AppAccess implementation, but complete user journeys remain due. | Real entry through the existing writer/service to durable effect and visible result, including populated stores, cold recovery and denied/no-effect cases. |
| Replacement and fork history | Reconcile the remaining C55 replacement and C57 fork/mixed-history work and its owned drafts. | Original-history preservation plus paired functional, backup and restore results. |
| Complete functional coverage | Reconcile the frozen requirements and all later regressions. The current pool is773 methods/45 groups, not the final coverage ceiling. Destination coverage includes35 enrolled but unexecuted methods and4 production-service methods still unenrolled/unexecuted. | Complete retained functional/compatibility evidence on the final candidate; no credit for unselected tests or results from older heads. |
| Qualified routes and affected UI | Retain exact native qualification for required execution kinds; Bitrise is held for exact-runtime availability/qualification. Verify affected expansion states in the existing S10 design system, accessibility and real human review. | Qualified same-head native/UI evidence, independent integration review and genuine human visual approval. Do not replay unrelated historical S10 states. |
| Remaining product choices | Resolve locked saved-detail editing and detailed-notification fields/wording from the existing product authority. | Explicit decisions and their implemented, verified journeys; no inferred scope reduction. |
| Main integration | Freeze the final candidate only after production adoption and corrections are complete. | All preceding gates, then the verified non-force fast-forward of main and required exact-main GitHub verification. |

## Execution order

1. Run four distinct destination groups concurrently after exact candidate/route review: review13, resolution7, discard7 and continuation7 (34 tests). They do not call parent finalization or the unresolved restore insert-records path. Shared persistence costs remain a risk, not a proven blocker. Use up to five GitHub slots when a fifth independent question is ready; Bitrise remains held for exact-runtime qualification.
2. Continue the parent-finalization performance diagnosis from its retained phase timings; batch only source-proven fixes and keep one collector per original.
3. Complete the remaining production journeys and enroll their missing regressions. Parallelize only disjoint, dependency-ready work on existing qualified capacity.
4. Freeze one complete candidate; collect final coverage and affected-state reviews, then advance and verify main.

Avoid checkpoint-only intermediate commits when they would create an untested parent. Prepare the next causal batch while an immutable, source-bound run executes; audit that original before its successor. Reuse unchanged evidence and qualified mechanical checks, not unverified assumptions or old native passes.

Merging is separate from release. Card135 stays owner-only/skipped; minimum-runtime and physical verification stay DEFERRED; `releaseReady=false`. No signing, distribution or submission is authorized here.

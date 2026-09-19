# Expansion into the existing AssetRounds app

Current navigation checkpoint, 2026-09-19. [CURRENT_INTEGRATION](CURRENT_INTEGRATION.md) controls scope and acceptance; [VERIFICATION_DUE](VERIFICATION_DUE.md) retains detailed obligations. Historical S10 is the accepted base, not a new workstream.

## Destination and present state

- `main` and `phase/s10-brand-refresh` both remain at accepted S10 `b1d04ae5e684aa9c6807af655089efa1df8a7ed6`.
- Work is on `codex/v23-s10-integration-20260910`, a descendant of that base. Latest audited native input is `e1a5507ce4334e73b9b54abab31d9392d45f2c01`.
- The branch has one `FieldEvidenceApp.xcodeproj`, one shared `FieldEvidenceApp` scheme and the existing app architecture. The remaining problem is completing and verifying its production integration, not combining two app projects.
- e1 native compilation passes on discard/continuation, with zero Swift errors/new warning signatures. Continuation passes7/7; discard passes6/7, with only initial-vs-durable timestamp equality failing. Parent1 and production4 did not start after the1200-second build limit. The current test correction preserves exact receipt time and canonical initial time; no epsilon or production predicate change.
- Parent Check/no-issue remains unresolved: prior6d exceeded900 seconds after parent/two-photo preparation640s and interrupted-target entry743s. The e1 synchronous validation optimization has no runtime measurement because its build timed out.
- 49 protected local drafts remain preserved; their presence does not mean they are reconciled, committed or accepted.

## Work required before main advances

| Workstream | What remains | Completion evidence |
| --- | --- | --- |
| Current native blocker | Verify the causal discard/resolution replay-clock corrections. Retain the parent phase diagnosis and measure the reviewed synchronous optimization when a justified build route permits it; avoid unchanged timeout retries. | Exact-head successful compilation and the original functional journey, preserving faults, assertions, protection evidence and budgets. |
| Production adoption | Finish C36 destination/restore correspondence and real receipt joins; child/finalizer recovery; Work/Round field, scene, focus and resume flows; lifecycle/codec/backup registration. Resolution and confirmed discard already have production-service/AppAccess implementation, but complete user journeys remain due. | Real entry through the existing writer/service to durable effect and visible result, including populated stores, cold recovery and denied/no-effect cases. |
| Replacement and fork history | Reconcile the remaining C55 replacement and C57 fork/mixed-history work and its owned drafts. | Original-history preservation plus paired functional, backup and restore results. |
| Complete functional coverage | Reconcile the frozen requirements and all later regressions. The current pool is777 methods/46 groups, not the final coverage ceiling. All39 destination methods are enrolled: at e1,13 passed,1 failed and25 remain unexecuted (review13/resolution7/production4/legacy1). ReceiptSafety55 and later causal cases still require reconciliation. | Complete retained functional/compatibility evidence on the final candidate; no credit for unselected tests or results from older heads. |
| Qualified routes and affected UI | Retain exact native qualification for required execution kinds; Bitrise is held for exact-runtime availability/qualification. Verify affected expansion states in the existing S10 design system, accessibility and real human review. | Qualified same-head native/UI evidence, independent integration review and genuine human visual approval. Do not replay unrelated historical S10 states. |
| Remaining product choices | Resolve locked saved-detail editing and detailed-notification fields/wording from the existing product authority. | Explicit decisions and their implemented, verified journeys; no inferred scope reduction. |
| Main integration | Freeze the final candidate only after production adoption and corrections are complete. | All preceding gates, then the verified non-force fast-forward of main and required exact-main GitHub verification. |

## Execution order

1. Verify the corrected discard7 and its source-proven resolution7 sibling concurrently on one reviewed causal successor. Preserve the e1 continuation7 pass without transferring it to a later head. Review/resolution/production/legacy coverage stays explicitly due; batch distinct groups only when dependency-ready and justified by new evidence. The last four concurrent builds took691s/1130s or hit1200s, so build cost and reliability limit throughput. Bitrise stays held: its public26.6 image does not list the pinned26.2 runtime. A same-provider build-sharing pilot needs separate moderate qualification; existing S10 reuse is not an enabled V23 route.
2. Continue the parent-finalization performance diagnosis from its retained phase timings; batch only source-proven fixes and keep one collector per original.
3. Complete the remaining production journeys and enroll their missing regressions. Parallelize only disjoint, dependency-ready work on existing qualified capacity.
4. Freeze one complete candidate; collect final coverage and affected-state reviews, then advance and verify main.

Avoid checkpoint-only intermediate commits when they would create an untested parent. Prepare the next causal batch while an immutable, source-bound run executes; audit that original before its successor. Reuse unchanged evidence and qualified mechanical checks, not unverified assumptions or old native passes.

Merging is separate from release. Card135 stays owner-only/skipped; minimum-runtime and physical verification stay DEFERRED; `releaseReady=false`. No signing, distribution or submission is authorized here.

# V23 phased merge readiness

Current development state and exact native outcomes: [ACTIVE_BRIEF](ACTIVE_BRIEF.md). Batch evidence and independent verdicts: [CURRENT_INTEGRATION](CURRENT_INTEGRATION.md). Open obligations: [VERIFICATION_DUE](VERIFICATION_DUE.md). This ledger defines phase scope; development results never establish acceptance.

As of 2026-09-26, Phase 1 is not merge-ready. Integration checkpoint `ea571505` is pushed; accepted S10 main remains `b1d04ae5`. Restore/history, Erase and report-production obligations remain open. AJ1 performance and AK1 localization successors are in development verification. All five same-head gates and genuine owner review remain required.

## Phased merge (owner decision 2026-09-25)

Main advances in phases. Each phase contains only journeys that are fully wired and verified, with every gate for that phase: same-head full unit coverage in timed partitions, qualified UI evidence (RUI1), one independent integration review, genuine human review of critical states, a non-force fast-forward and exact-main verification. No incomplete schema, persistence, backup or restore change may merge. Unfinished features stay unreachable and are listed below with their remaining work. Release still requires the full V23 scope.

Inventory basis (read-only census at 31126e9, 2026-09-25; retained in the session scratch `p04-inventory/cards.json` and `coverage-census/`): no production code creates a Round or publishes an inspection package release, so the C36 Round capture journey cannot be reached by a real user yet. The versioned schema is one chain (V1–V53, live V53) and every phase ships the whole persistence format. Main is not released, so later phases add schema stages through the normal migration chain.

### Phase 1 — platform and shell (root decision, 2026-09-25)

- Contents: migration from real S10 stores; the sole writer and receipt journal; generation leases; startup recovery; backup, validate, restore, replace and Erase for every family (families without entry points stay empty); the four-tab shell with place restoration, App Lock and typed settings; the accepted S10 sign and report journeys re-verified inside the new shell. Persistence format: V53 as at HEAD.
- Made unreachable through one runtime gate `V23PhaseGateV1` (shipping = phase 1; nothing persisted; tests inject all features). This follows a read-only reachability audit at 7e0639b, which found these Release-reachable surfaces: the Today Plan sheet and dormant "Available work" list (replaced by a minimal honest empty state, human-reviewed); the dormant Work current-work list with its Round and saved-draft rows (routes and the saved-review sheet are kept for restoration); Settings › Reminders (nothing can be scheduled, yet enabling it prompts for notification permission); the three App Intents (declared non-discoverable per type and gated in `perform`); the dead `.arenvelope` document-open claim in Info.plist; and camera permission text mentioning video (restored to S10 wording). Reachable and complete in phase 1: Work › Completed work signoff, Settings › App Lock, and the four-tab shell. The unused microphone and speech-recognition permission strings are listed for release review. Main is not released before every phase is complete, so a later-phase backup cannot reach a phase 1 user; gated data restored in development stays stored and Erase removes it.
- Gates: same-head coverage of every unit method through the shared-build partition route (owner decision 2026-09-25) after one early development sweep; the notification/schedule/Erase 28 set; the startup interrupted-finalization case; a reviewer check of the backup/Erase registration gaps found by text search; qualified RUI1 UI evidence; one independent integration review; genuine human review of critical states; non-force fast-forward and exact-main verification.

- Restricted persisted-format items in the Phase 1 candidate (each must pass all five gates before main):
  - aggregate migration journal schema 2, with framed layered semantic digests V3…V53 and a schema-2 final aggregate manifest (batch O). This fixes the S10 → V23 upgrade blow-up.
  - the backup restore readback shares the export's archive receipt order (batch N). Archive bytes are unchanged.

  - Mutable-semantic checkpoint v2 (batch Q; implicit version, all 148 kinds). R2 restore/upgrade evidence is required.
  - Batch U C11/C12 typed postimage/history census, optional reversal-plan validation and C18 package promotion/replay/complete-closure corrections: independently reviewed, locally compiled/tested and pushed4a8c0ea1. Same-head hosted persistence/restore gates remain required.
  - Batch V restore claim recovery/digest ordering, My Day/portable corrections and immutable legacy package bridge: combined builds passed; V4 affected45/45PASS, V7 deletion/recovery3/3PASS and V9 new C49 history casesPASS. Genuine clone remains blocked by six destination journal projection gaps, now exactly attributed by V10; C49 class retains3failures and V9_03 migration remains unresolved. Forward-only claim locations and all restricted-change gates remain explicit; no phase acceptance.
  - Batch T C13 concurrency/domain postimage binding and configuration-clone omitted-draft destination projections. Receipts and revision history remain preserved; complete restore/relaunch coverage remains required.
  - Batch S/T writer lease and per-operation file-authority proof performance changes retain fencing and file-policy predicates; full hosted coverage remains required.

- Decision 17 numbers (sweep 36218186328 at 27388c99; 437 failures; reviewer triage):
  - Phase 1 core, never eligible: ~346.
  - Switched-off feature workflows (B): ~49, about 11%, each needing per-method confirmation.
  - Infrastructure/anchor/localization (C): ~41, which bind Phase 1 apart from possibly part of S9_1.
  - Root recommendation: no known-failures list; fix to green.

### Phase ledger (later phases; nothing silently dropped)

| Card | Status at 31126e9 | Remaining work | Blocking dependencies |
| --- | --- | --- | --- |
| P04-C05 Round state machine | Wired, unverified | Production Round creation and published package source; enroll V9_70 | P03-C18, C21/C22 |
| P04-C06 Offline readiness | Wired; readiness 6/6 native at 31126e9 | Cold-launch preflight; enroll V9_71 | C05 |
| P04-C07 / P03-C36 Round capture | Wired, unverified (completion 7/12, mount 1/7) | Continue failure fix, B3 Retake/Remove with backup, photo-save crash gap, stage A items, handoff/recovery/closeout, enroll V9_26, RUI1, human review | C05, C06 |
| P04-C16 Shell/settings/lock | Wired, unverified | Practice workspace (V51) unwired; coverage, RUI1, human review (Phase 1 core) | P02-C11, C01 |
| P04-C22 Recurring rounds/reminders | Settings only | Schedules, recurring start, due queue, history; notification 28 set; RUI1 | P03-C28, C07, C09, C16 |
| P04-C41 My Day / P03-C57 | Wired, dead actions | Wire actions; V54 fork lineage (amendment approved); enroll planning classes; C57-1 replacement projection reviewed | P03-C57, C12, C22 |
| P03-C43 completed-work signoff | Design complete; batch 1 in implementation | Owner purpose/role decided 2026-09-25; journey, backup/restore, RUI1 | Incumbent finalize only |
| P04-C01 Recovery Center | Unwired | Settings entry, encrypted-backup option | P03-C22, C54 |
| P04-C02/C03/C04 | Unwired (V43/V44 live) | Evidence, sign-playbook and shop-profile entries | P03-C24, C01, C02 |
| P04-C08, C10–C13 | Unwired (V46–V50 live) | Entry points | C02, C07–C11, P03-C37 |
| P04-C09 Dashboard | Unwired | Route from Assets/Reports | P03-C53 |
| P04-C14 System discovery | Unwired, intents exposed | Install runtime and settings, or keep intents excluded | P03-C20, C34, P02-C11 |
| P04-C17–C25 | Unwired, no views (V52/V53 live) | Build UI | P03 owners, C12, C16 |
| P04-C27/C28 | Test corpora only | Re-run per phase; polish before release | C26/C27 |
| P04-C30/C31 | Factories called only by tests | Label and handoff UI | P03-C45/C46 |
| P04-C32–C40, C42–C45 | Unwired | Entry points; older-head passes only for C33/C34/C38 | P03-C46–C56, C08, C16 |
| P04-C44 Parts & Stock / P03-C55 | Unwired (restore runs it) | Owner decision on `C55_REVERSAL_RESTORE_DECISION.md`; production report-byte preservation on Clone/Fork (C55-1 finding) | P03-C55 |
| P04-C15, C26, C29 | No app code (prepare-now) | Owner and release preparation; C29 is the final freeze | — |

## Destination and present state

- `main` and `phase/s10-brand-refresh` both remain at accepted S10 `b1d04ae5e684aa9c6807af655089efa1df8a7ed6`.
- Committed implementation, current native outcomes and the next causal question are recorded in ACTIVE_BRIEF; historical diagnostics stay in CURRENT_INTEGRATION and their sealed original audits.
- The branch has one `FieldEvidenceApp.xcodeproj`, one shared `FieldEvidenceApp` scheme and the existing app architecture. The remaining problem is completing and verifying its production integration, not combining two app projects.
- Parent-finalization performance and its unexecuted coverage remain explicit obligations in VERIFICATION_DUE. Reuse its retained phase timings and diagnosed work; do not infer a new cause from old log volume.
- 55 protected local inputs remain preserved; their presence does not mean they are reconciled, committed or accepted.

## Work required before main advances

| Workstream | What remains | Completion evidence |
| --- | --- | --- |
| Current native question | Follow ACTIVE_BRIEF for the current frozen development candidates and actual results. AI1 recovery/photo9/9 passes locally, while its restore/transport selections retain five failures; isolated report production and current AJ1/AK1 follow-ups have separate source bindings. Earlier startup, C36, notification and full-coverage obligations remain due. | Sole collection, exact executed-selector/source audit and risk-appropriate independent review of each coherent checkpoint; all required same-head gates before main. |
| Production adoption | Finish C36 destination/restore correspondence, Release-authorized staging review writes, cross-workspace photo-child remapping and authenticated retained review/photo closure; child/finalizer recovery; Work/Round field, scene, focus and resume flows; lifecycle/codec/backup registration. Resolution and confirmed discard already have production-service/AppAccess implementation, but complete user journeys remain due. | Real entry through the existing writer/service to durable effect and visible result, including populated stores, cold recovery and denied/no-effect cases. |
| Replacement and fork history | Reconcile the remaining C55 replacement and C57 fork/mixed-history work and its owned drafts. | Original-history preservation plus paired functional, backup and restore results. |
| Complete functional coverage | Reconcile frozen requirements and later regressions using VERIFICATION_DUE. The committed selector pool is not the final coverage ceiling; enrollment, execution, artifact integrity and acceptance are separate. | Complete retained functional/compatibility evidence on the final candidate; no credit for unselected tests or older heads. |
| Qualified routes and critical UI | Qualified GitHub may cover all required execution kinds; Bitrise is optional when it adds no required coverage and remains held until qualified if used. Verify critical expansion journeys, S10 design-system behavior and accessibility. | Same-head required native/UI evidence, one independent integration semantic review with automated index/commit binding, and genuine human review of critical states. |
| Noncritical visual polish before release | Cosmetic completeness only may follow merge, with explicit items in VERIFICATION_DUE. Functional, privacy, accessibility and unusable-state defects remain merge blockers. | Genuine human review and closure before release; no silent deletion of a visual obligation. |
| Reminder verification | Real Settings mounting, saved Preferences, permission handling, retry/error behavior and Erase owner replacement are implemented; the20 relevant source/test paths are unchanged from audited d83 Reminder33PASS. Complete the enrolled populated notification-schedule-erase28 boundary before the new Finding/profile/recurrence1054 transition, remaining affected coverage and actual UI/OS interaction. A six-state human checklist is prepared; five C22 UI methods still skip. The focused witness is source-reviewed only and native UI route/build-budget qualification remains due. Keep the earlier intermittent cause unresolved. | Exact current-head native coverage, real UI/OS behavior, affected S10 visuals and genuine human review. The d83 pass remains head-specific; no repeated implementation or acceptance transfer. |
| Main integration | Freeze the final candidate only after production adoption and corrections are complete. | All preceding gates, then the verified non-force fast-forward of main and required exact-main GitHub verification. |

## Execution order

1. Complete the current bounded local compile/affected-test cycles. Address proven restore, migration, ownership and report-production prerequisites by family, preserving historical failures and exact evidence scope.
2. Integrate reviewed candidates through small coherent integration-branch checkpoints. Keep subsequent work isolated while a checkpoint runs; use affected verification and repeat full development coverage after meaningful stabilization.
3. Freeze a Phase 1 candidate only after its required functionality and data-safety work are complete. Pass every unit partition, qualified critical UI evidence, independent integration review and genuine owner screenshot review on that candidate.
4. Fast-forward main non-force, then perform exact-main verification on the pinned GitHub route. Continue the later feature ledger under AGENTS.md; unfinished features stay gated until their phase requirements pass, and full V23 scope remains required before release.

Root alone commits, pushes and dispatches. Reuse relevant helper context and unchanged evidence only within its exact scope. No local or hosted development result becomes gate evidence. Integration cadence follows owner decisions 21–23 in AGENTS.md; the historical slower checkpoint rule is superseded.

Merging is separate from release. Card135 stays owner-only/skipped; minimum-runtime and physical verification stay DEFERRED; `releaseReady=false`. No signing, distribution or submission is authorized here.

Infrastructure priority: audited35566904385 build1088s/tests686s/job1930s; prior35563517738 build919s/tests522s/job1609s. No causal speedup claim from variable runs. Restore882/peer helpers qualified and adopted after audit; prepare disjoint questions on a consistent next-head helper baseline, then actual independent route/cohort/command gates. Bitrise exact iOS26.2/23C54 remains unavailable in retained26.6 stack1f4c6fe6 evidence. Keep cold/miss-safe qualification and final provider gates.

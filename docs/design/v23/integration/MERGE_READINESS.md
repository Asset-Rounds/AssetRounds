# V23 phased merge readiness

Current development state and exact native outcomes: [ACTIVE_BRIEF](ACTIVE_BRIEF.md). Batch evidence and independent verdicts: [CURRENT_INTEGRATION](CURRENT_INTEGRATION.md). Open obligations: [VERIFICATION_DUE](VERIFICATION_DUE.md). This ledger defines phase scope; development results never establish acceptance.

As of 2026-09-28, Phase 1 is not merge-ready. Latest pushed CI-only checkpoint `d7bb1c976` preserves product source `e74df72d0`; accepted S10 main remains `b1d04ae5`. Its independently reviewed passive D50 tooling passed52/136(+3optional historical skips)/42/380 checks. Hosted original36440846353 then timed out at the unchanged1800s build limit:0SwiftErrors,14NotStarted,64manifest files SHA-verified. The bounded compiler-parallelism development experiment has source review6af0e6da and full tooling54/138(+3optional skips)/42/381 PASS on2696unchanged inputs; exact9CI paths passed staged review47dc7a51 and were pushed non-force asd7bb1c976. Distinct hosted development36451514209 completed: buildPASS1700s,14tests4PASS10FAIL; solecollector95387 terminal and1267manifest hashes verified. Compiler comparison is complete; differing host pressure and censored prior build prevent causal speedup attribution. Two reviewed local policy fixes now pass full305build and3affected native tests; exact six-path checkpoint is under staged review, pinned26.2 verification remains due. The bounded local S6 17-cut interruption method passed with full305-test compilation; full S6 coverage remains due. Isolated C05 compiler-correction v4 passed603-app DEBUG/nondebug module checks, while later R-entry/Registry settlement, V949 cold-source/SHM preservation and complete C05 recovery remain incomplete and uninstalled. Current ordered census3660methods/33partitions is not a coverage execution. All five same-head gates, cold route qualification, genuine owner visual review and complete later-phase V23 scope remain due. CURRENT_INTEGRATION retains exact historical results. No acceptance, main advancement, signing or release has occurred.

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
| Current native question | Follow ACTIVE_BRIEF and CURRENT_INTEGRATION for the current pushed checkpoint and separately sealed isolated candidates. AP9 affected native ran 58 actual methods (52 pass/6 fail); AS2 ran four actual diagnostic methods (0 pass/4 fail); reviewed AS3 recovery corrections then compiled and ran two affected methods (1 pass/1 fail). These are isolated development scopes, not current-head full coverage. Preserve the remaining migration, restore, startup, backup, report-production and Erase obligations. | Exact source/product and executed-selector audits, bounded correction by observed family, risk-appropriate independent review before a coherent integration checkpoint; all required same-head gates before main. |
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

2026-09-27 storage blocker: repeated ENOSPC now prevents source writes and verification. Safe partial handoffs retained; no source/runtime/gate completion inferred. See ACTIVE_BRIEF and latest CURRENT_INTEGRATION checkpoint.

2026-09-27 storage update: owner-authorized obsolete output cleanup recovered about24.2GB; storage blocker cleared. No verification obligation is closed; full details/receipts in latest CURRENT_INTEGRATION.

2026-09-27 development update: ownership/diagnostic full304Swift compile passed; exact13native selection6PASS7FAIL246.221s collected with unchanged sources/products. Shared owner retired-source recovery now passes; protection-stage physical witness, AppAccess return, deterministic revoked-reader no-effects evidence and C46 serviceParty projection remain open. Selection-generator42 passed; native-CI v2 still running. No gate or main advancement. See CURRENT_INTEGRATION for exact bindings.

2026-09-27 current development checkpoint: full304Swift compile PASS96.203s; exact9 native5PASS4FAIL124.894s collected with unchanged source/products. C46R01 and twoC32 controls now pass; S6/V906 and twoV949 cases remain open. Frozen12-path intermediate checkpoint review/publication due; no main or gate advancement. See CURRENT_INTEGRATION latest checkpoint for bindings and diagnostics.

2026-09-27 hosted development preparation: primary27-selector candidate required CI suites42+379PASS with2,691inputs unchanged, exact reviewed protection pin/history assertion updated; publication/dispatch due. Its app runtime scope remains earlier6=2PASS4FAIL. Later live Restore/abort composition full304compilePASS69.944s, native16 terminal9PASS/7FAIL123.199s with source/products unchanged and evidence retained as m2-restore-abort-root-v1-20260927, separate from hosted candidate. All same-head gates/main and full V23 obligations remain open.

2026-09-27 AP10 bounded local follow-up: all7 current-source assurance/backup selectors PASS106.390s, source/products unchanged, retained m2-ap10-assurance-current-v1-20260927. Covers five S4_5 assurance controls and S6_3 golden mixed package/invalid families only. No gate evidence or broad backup-family closure; schema-pair/photo/archive/full-coverage obligations remain.

2026-09-27 hosted4bc development36368867150: buildPASS1194s, tests17PASS10FAIL/261s, all27selected methods executed. Six pinned-runtime retirementPolicyEffectUnavailable failures require genuine checked policy effect ownership; no pending-policy acceptance shortcut. Two uncertainOwner, one V949invalidAuthority and one nondeterministic no-admission summary comparison remain scoped failures. Complete1275-file manifest verified; local passes do not override this hosted result. No rerun/gate credit. Compiler565warning occurrences retained, no new-warning attribution yet.


2026-09-28 latest: frozen intermediate snapshot independently approved6e3451af for development integration only; full305 compile PASS, exact5native FAIL and CI421PASS,3656-method census. Newer isolated recovery source compiled PASS and18native14PASS4FAIL, exactsource/products,1362artifacts268products retained. S6 interruption classification, nonempty fixture graph, V906 post-ready cleanup and V949 hostile inventory remain;24.4GiB allocated heap/large swap remains a performance blocker. No main/gate/release advancement; see CURRENT_INTEGRATION for separate exact scopes.


2026-09-28 latest bounded development: combined305compilePASS and16native14PASS2FAIL with exactsource/products retained. Nonempty journal and V906 now pass; S6 later authority and V949 SHM-only physical comparison remain. Framed canonical proof parity/hostiles pass with sampledpeak0.754GiB; broad performance/gates remain unverified. These newer live results do not apply to published da388ed4. See CURRENT_INTEGRATION for hashes/scopes.


2026-09-28 shutdown diagnostic follow-up: full305 compile PASS50.174s; exact2-native1PASS1FAIL238.371s,1356artifacts268products retained. Genuine retained-marker replacement/wrong-operation/extra-leaf refusal now passes17.760s. S6 interruption remains blocked at post-retired stable-tree comparison after checked close/unlink, with no weakened guard; V949/C05 cold private-copy ownership remains incomplete and isolated. Frozen framed checkpoint has conditional independent Sol-high review15b08346 and generator42PASS; required native-CI379 and staged-tree review pending. No main/gate/release advancement.


2026-09-28 latest: full305 first-difference diagnostic compilePASS169.905s; one S6 nativeFAIL220.096s with source/products unchanged,1324artifacts268products retained. First mismatch is owner-directory link count after checked owned-guard unlink; exact correction pending. C05 isolated603-input envelope3 modulePASS125.384s (compiler closure only); positive schema2/V3 owner/private-copy lifecycle remains incomplete/noninstallable. Frozen framed checkpoint v2 retains exact14PASS2FAIL app source and complete3658 census; optional hash selector remains local-PASS/full coverage but excluded from the focused14-selector hosted list because the strict class-file route cannot admit it. Independent conditional reviewb23efeca; generator42PASS, native-CI379 pending. No main/gate/release advancement.


2026-09-28 framed checkpoint v2 CI complete:42+379PASS on2696 unchanged inputs; ten exact app/test/CI paths transferred to primary, pending staged review/commit. Its305compilePASS and16native14PASS2FAIL remain the exact development scope, not merge readiness. Later live corrections remain isolated; S6/V949 and full gate obligations stay open.


2026-09-28 checkpoint f869dd07b pushed after independent Sol-high exact staged review00b2c558/tree08e52e7a, required421CI PASS and retained local14PASS2FAIL. Hosted DEVELOPMENT original36425436253 now running on that exacthead with14selectors; solecollector58467 active. No main/gate/release credit; later local marker/diagnostic/C05 work remains isolated.


2026-09-28 later local owner-link correction: full305compilePASS122.138s;2native1PASS1FAIL259.991s,1328artifacts268products retained. Exact one-owned-file link transition/hostility control passes and real shutdown advances; S6 later cleanup-manifest/completion-directory family remains unresolved. Not evidence for frozen hostedf869dd07b or a gate.


2026-09-28 S6 local interruption family: all17 cuts in the existing Every method now PASS249.442s (native283.348s), exact source/products,1328artifacts268products retained; latestfull305compilePASS16.019s. Earlier owner-link and marker hostility passes retain exact earlier input scopes. Full S6 coverage, V949 cold-source correctness and all merge gates remain due; hostedf869dd07b is older source and receives no transferred local pass.


2026-09-28 hosted36425436253 atf869dd07b terminal build timeout1800s,0SwiftErrors/571warnings,all14NotStarted;62 retained manifest hashes verified. Compiler bottleneck diagnosis due; no rerun or budget relaxation. No hosted functional/gate credit. Next bounded S6 checkpoint3660census/33partitions is under requiredCI15883/independent staged review; local17-cut pass does not replace hosted verification.


2026-09-28 S6 closure checkpoint: required42+379CI PASS,2694 inputs unchanged; exact six app/test plus coverage JSON transferred,1204 source hashes match local305compile/17-cut EveryPASS. Staged review/commit pending; no hosted/gate credit. Hosted f869 build-timeout diagnosis cannot isolate source versus runner load; measured profiling next, budgets unchanged. V949/C05 and legacy partial-delete compatibility remain open; main unchanged.


2026-09-28 S6 closure checkpoint published as e74df72d0 after independent nonauthor Sol-high staged reviewfb01b955b6c454e0d3f0c26beb09f640ad66c0b1ed850ea41c8bb7e65b8eb78d/tree6f5af5c8149db86de42c83a3e077eebe0cf349c9. Eleven explicit paths, required421CI PASS, exact local305compile and17-cut method PASS; fresh remote refs before commit/push, non-force linear push, main unchanged. Owner config preserved/unstaged. No new hosted dispatch; bounded exactf869 app typecheck profiling is diagnostic-only and underway with separate cache.


2026-09-28 C05 private-reader v8 isolated603-app modulePASS85.567s, snapshot/live unchanged after independent access/composition reviews. No live/native/full cold recovery evidence. Next typed preactivation/phase-CAS work is isolated; full forward cleanup and all gate obligations remain open. Passive hosted diagnostic V1 rejected; default-off bounded successor in scratch, no dispatch.


2026-09-28 passive D50 V4 full tooling is not green: timing52 and selection42 pass; dispatcher136pass/3optional historical-module skips; native379run reports12historical-adapter/branch expectation failures, all2695inputs unchanged. Exact bounded test successor and independent review/full CI remain due. No diagnostic source installed or dispatched; main unchanged.


2026-09-28 exactd7bb hosted development36451514209 complete: buildPASS1700s step within1800s budget; all14selectors executed4PASS10FAIL. Sole collector95387 terminal; all1267 manifest files independently SHA-verified. Failure families include retirement policy, identity, admission, journal and fresh coordinator; diagnosis/corrections remain due. No gate credit or main advancement. New isolated C05 publication app/test module checks pass their exact scopes; full cleanup/replay/ready and native remain unfinished.


2026-09-28 two hosted-policy fixes independently reviewed and local full305buildPASS40.573s plus affected3nativePASS305.173s; source/products unchanged,1464artifacts268products retained. Fixes cover early original-Erase authenticated policy request and maintenance-journal published policy. Pinned26.2 verification remains due, as do target-manifest/admission/other hosted families, full cold deletion/replay/ready and all gates. Main unchanged.

# Current Task

## Program and card

- Phase / branch / card / global order: `S6 / phase/s6-data-rights / S6.6 / 26 of 36`.
- Card heading: `### S6.6 — Resumable Erase All`.
- Position / boundary / immediate next card: `6 of 6 / phase boundary yes / S7.1 only after accepted S6.6 evidence, green phase and exact-main integration, next-branch hydration, and fresh transition G0`.
- Program autopilot / phase autopilot / exact S6 span / boundary integration: `enabled through accepted S9.1 / enabled / S6.1,S6.2,S6.3,S6.4,S6.5,S6.6 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S6 phase-main base: `P=7c3c381055abde6f6b1020a9f3f599333ef47f40`; this is the accepted S5 HANDOFF-only phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S6, including S6.6 implementation and boundary verification.
- Integrated/card base: `M=b2e8a8170d55872c93ec4611b7ef82ecb7890247`; this is accepted S6.5 product and verification evidence on `phase/s6-data-rights`.
- Accepted S6.5 workflow evidence: run `31812947145` / job `94807703697`, exact `phase/s6-data-rights@M`, attempt 1, F25/UI enabled, terminal success, `5/5` units and `1/1` UI green; URL `https://github.com/palatis3/AssetRounds/actions/runs/31812947145`.
- Accepted S6.5 artifact: `ios-ci-31812947145-1`, ID `9224539028`, size `9396892`, GitHub digest `sha256:99c1dbd452c2d97af2fe7ec2c970a01b38f697f8fca161134944e6562e2a5029`; `SHA256SUMS.txt` SHA-256 `2EB223006B1CE8B920C10F3CA036FD51F09DB000A60362A11C49C3B2E17947CF`; all `101/101` listed payloads independently matched; terminal screenshot SHA-256 `81B87097F1E29F2A52A6A9D8072A01C8BF1FD10F0BC314E07FF6A47931BD848A`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- S6.5 recovery provenance remains immutable: failed candidates `31805457695`, `31806931401`, `31808369300`, `31810267694`, and `31811922051` were diagnosed, corrected by successive direct children, and never accepted or rerun by run ID.
- Mandatory later integration evidence remains frozen: a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. That reusable seam remains outside S6.6 and must be exercised and corrected by S8.1 before release.
- Task-start authority A is the direct-child S6.6 transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child commit changing only an append to `docs/execution/HANDOFF.md` plus this replacement `docs/execution/CURRENT_TASK.md`; remote `phase/s6-data-rights=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S6.6 plan anchors: `## 7. Free evaluation, subscriptions, and payments` → Erase All resets only accepted device-local evaluation state and remains separate from Apple billing; `## 10. Storage, crash consistency, and one-off bug prevention` → immutable generations, exact current/retired pointers, no active-store deletion, named auxiliary roots, and closed recovery; `### V4Backup@1` → exported Files remain outside erase scope; `## 11. Build slices and release gates` → S6.6 journaled empty-generation pointer switch; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S6.6 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S6.5 compact JSON plus LF, 344 bytes, SHA-256 `92DADA795227BD92E1B0A39D7FB47279C35BB95E056ECC430ADE1C4EECA725FE`; after G0 the first support mutation replaces it with the exact S6.6 object below, 336 bytes, SHA-256 `8EE33FCE260474843CD33FBF8565C0FE19248AA19B550F4FB59542E41B191BC2`.

## Outcome and acceptance

- Outcome: add typed **Erase All** confirmation and one recoverable operation that prepares a fresh validated empty generation, journals an exact four-phase pointer/session transition, activates that generation without deleting an active store, drains old references, deletes only the frozen old generations and named auxiliary state, recreates exact-zero diagnostics, and removes its marker only after complete verification.
- Entry/precondition truth: Settings exposes Erase All for a proven valid active session. Startup maintenance exposes it only when the current generation is independently proven valid and there is no active or malformed Restore or Erase journal. Feature mutation remains blocked while Erase authority exists. Pointer-invalid, generation-missing, or active-journal maintenance never guesses or broadens the target set.
- Confirmation/cancel truth: the destructive action requires the exact typed value `ERASE`. Cancel before marker creation changes no byte, row, counter, pointer, generation, auxiliary root, UserDefaults domain, diagnostic, entitlement, StoreKit state, external backup, or UI session.
- Intent truth: canonical `Application Support/FieldEvidenceErase/erase.json` has exactly `auxiliaryRoots`, `eraseID`, `generationIDsToDelete`, `newGenerationID`, `oldGenerationID`, `phase`, and `schemaVersion`. `generationIDsToDelete` is the unique sorted set of every validated existing generation except the frozen new generation. `auxiliaryRoots` is exactly `FieldEvidenceRestore/`, `FieldEvidenceOperations/`, `FieldEvidenceCommerce/`, all `FieldEvidenceDiagnostics/`, `Library/Caches/FieldEvidenceApp/`, `tmp/FieldEvidenceApp/`, and the app bundle ID's UserDefaults persistent domain.
- Phase truth: phases are exactly `empty_generation_prepared|pointer_switched|session_activated|cleanup_complete`. Prepared means a complete independently validated empty generation exists while old remains current. Pointer switched means canonical `current.json` names new. Session activated means the new empty container/root is the sole coordinator authority. Cleanup complete means every frozen noncurrent target and named auxiliary state is removed or reset, diagnostics are exact zero, live and tombstoned counted roots are zero, and the new generation remains current and empty.
- Storage/authority truth: pin and no-follow every target ancestry and exact directory identity before mutation; reject malformed, missing, extra, substituted, symlinked, special, hard-linked, colliding, or ambiguous authority without deleting anything. Never enumerate or delete beyond the frozen generation IDs and exact named auxiliary roots. Never delete, rename, overwrite, or recursively remove the active generation/container.
- Pointer/session truth: atomically install and fsync the empty generation and exact current pointer, then rebuild `StoreSessionCoordinator` once from that new generation. The old container and frozen noncurrent generations may be deleted only after prior references drain; otherwise cleanup waits for a later cold launch. Retired IDs become exactly consistent with the one surviving current generation.
- Auxiliary/zero truth: after session activation remove only frozen Restore/Operations/Commerce/Diagnostics roots, FieldEvidence app cache/temp roots, and the app bundle's local defaults domain; recreate the canonical zero diagnostics object; prove zero Site/Asset/WorkflowRecord/EvidenceFile/Issue/Packet/Report rows, zero live or tombstoned counted roots, no app-owned evidence/snapshot/PDF/staging bytes, and no Erase marker after completion.
- Recovery truth: run Erase reconciliation before Restore and ordinary pointer maintenance. At `empty_generation_prepared`, old-pointer plus valid empty new resumes the switch and new-pointer plus valid empty new advances. At `pointer_switched`, old-pointer plus valid empty new performs the named switch and new-pointer plus valid empty new activates/rebuilds. At `session_activated`, new must be valid/current/empty and a cold launch completes any remaining subset of only frozen cleanup. At `cleanup_complete`, new remains valid/current/empty and remaining frozen cleanup is completed/reverified before marker removal.
- Fail-closed matrix: a pointer naming neither old nor new; missing, nonempty, invalid, or extra generation; generation outside the frozen set; unexpected auxiliary root; malformed intent; unknown phase; active Restore collision; dirty context; or mismatched current/retired authority opens maintenance and deletes nothing. An exactly named phase-lagged pointer resumes idempotently.
- Subscription/external truth: Erase never calls StoreKit product loading, sync, purchase, restore, manage, cancel, or transaction mutation and never claims to cancel the Apple subscription. It does not erase App Store state or exported `.fieldrecordbackup` packages outside the app container.
- GOLDEN: interrupt before and after every pointer and phase write across all four phases, cold relaunch before ordinary pointer maintenance, and finish at one fresh active validated empty generation, zero live/tombstoned roots and diagnostics counters, only frozen old IDs removed after references drain, no marker, and zero StoreKit sync/cancel calls. The bounded UI flow proves typed confirmation, exact separate-subscription copy, generation rebuild, and one Accessibility XXXL terminal screenshot.
- ALT-1: Cancel before marker creation changes no byte, row, counter, pointer, generation, root, auxiliary state, external package, entitlement, or StoreKit state.
- Accessibility/UI: reuse Worklight semantic components; provide exact destructive context and separate-subscription copy; preserve logical focus/order, non-color state, at least 44×44 controls, and every Dynamic Type category; lock duplicate activation; keep Cancel and destructive completion reachable at Accessibility XXXL.
- Forbidden behavior: active-container deletion; OS-container wipe; filesystem target discovery beyond the exact frozen roots/IDs; StoreKit cancel/sync/manage/purchase/restore; entitlement mutation; exported-Files deletion; evaluation ledger beyond Packet roots; partial row deletion; live-store overwrite; newest-directory guess; noncanonical pointer/journal; automatic repair/migration; schema/model/project/package/capability/permission change; S7 commerce behavior; backend/cloud/account/sync; signing, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s6-data-rights`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S6.6","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S6_6EraseRecoveryTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S6_6EraseAllUITests"]}` plus exactly one LF; 336 UTF-8 bytes, no BOM; SHA-256 `8EE33FCE260474843CD33FBF8565C0FE19248AA19B550F4FB59542E41B191BC2`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. After accepted S6.6, boundary authority additionally allows HANDOFF-only phase close, exact phase verification, verified non-force `main` fast-forward, exact-main verification, frozen S7 branch creation, and S7.1 authority hydration. Force-push, merge commit, PR, ref rewrite/delete, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift`
- `FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift`
- `FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift`
- `FieldEvidenceApp/Features/Settings/EraseAllView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`

Test paths:

- `FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift`
- `FieldEvidenceAppUITests/S6_6EraseAllUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, script, workflow, authority, or documentation path is allowed during S6.6 implementation. Existing immutable-generation, Restore, pointer, session, diagnostics, navigation, design-token, StoreKit-free, report/media/snapshot, canonical-JSON, and storage-preflight seams may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0, verification, and phase boundary

- Fresh G0 must prove clean `phase/s6-data-rights`, `A^=M`, exact one-commit HANDOFF-append-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins, accepted S6.5 exact-head run/artifact, accepted S6.5 selector byte-exact, and the ten-production/two-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S6.6 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S6.6 CI, read `KNOWN_BUGS.md`, append the immutable S6.6 HANDOFF, and commit/push the HANDOFF-only phase-close head C. Verify exact phase C first; then, only after a fresh ancestry/ref check, non-force fast-forward `main` from P to the exact accepted phase-close/verification head and require green UI-enabled exact-main CI.
- Only after accepted exact-main S6 integration may program autopilot create `phase/s7-commerce` from that exact green main head, hydrate immediate-next S7.1 CURRENT_TASK only, push without force, and run fresh S7.1 G0. The already frozen S7.1 fixture facts are product ID `com.palatis3.fieldrecord.sub.solo.monthly.v1`, 14-day introductory offer, 16-day paid-to-paid grace, and Family Sharing off; they are not a new owner-input gate.

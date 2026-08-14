# Current Task

## Program and card

- Phase / branch / card / global order: `S6 / phase/s6-data-rights / S6.4 / 24 of 36`.
- Card heading: `### S6.4 — Empty-install atomic restore and presence-matrix recovery`.
- Position / boundary / immediate next card: `4 of 6 / phase boundary no / S6.5 only after accepted S6.4 evidence and fresh transition G0`.
- Program autopilot / phase autopilot / exact S6 span / boundary integration: `enabled through accepted S9.1 / enabled / S6.1,S6.2,S6.3,S6.4,S6.5,S6.6 / yes at S6.6 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S6 phase-main base: `P=7c3c381055abde6f6b1020a9f3f599333ef47f40`; this is the accepted S5 HANDOFF-only phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S6.
- Integrated/card base: `M=2a6c5316112f90902f05a55e1fa4b0c67ece457c`; this is accepted S6.3 product and verification evidence on `phase/s6-data-rights`.
- Accepted S6.3 workflow evidence: run `31794139948` / job `94747368022`, exact `phase/s6-data-rights@M`, attempt 1, P12/UI enabled, terminal success, `2/2` units and `1/1` UI green; URL `https://github.com/palatis3/AssetRounds/actions/runs/31794139948`.
- Accepted S6.3 artifact: `ios-ci-31794139948-1`, ID `9217114043`, size `5363060`, GitHub digest `sha256:9102e7ac06bd1161c14d3c7c471879753d6d5490522a171f62ec92b4e923b9a0`; `SHA256SUMS.txt` SHA-256 `1C0C9C4607D0A58F9B90FD885A82EB9B30159A82D1713FEBD372DA551B1B2D39`; all `95/95` listed payloads independently matched; terminal screenshot SHA-256 `1CE4B0C385BF98AD4F53079B3D544F93E49EECD39C0E0E764750104FFB0B64F1`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- S6.3 recovery provenance remains immutable: failed candidates `31790379517`, `31790797942`, `31792129516`, and `31792782350` were diagnosed and never accepted or rerun by run ID; successive direct-child corrections culminated in accepted M.
- Mandatory later integration evidence remains frozen: the accepted S6.3 UI proof used a cold boundary because a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. That earlier reusable seam is outside S6.4 and must be exercised and corrected by S8.1 before release.
- Task-start authority A is the direct-child S6.4 transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child commit changing only an append to `docs/execution/HANDOFF.md` plus this replacement `docs/execution/CURRENT_TASK.md`; remote `phase/s6-data-rights=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S6.4 plan anchors: `## 10. Storage, crash consistency, and one-off bug prevention` → immutable generation roots, restore capacity, exact seven-key journal, atomic pointer switch, and the closed phase/presence recovery matrix; `### V4Backup@1` → validated schema-1 package, pending/failed report semantics, and no commerce/diagnostic import; `## 11. Build slices and release gates` → S6.4 empty atomic restore/recovery; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S6.4 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S6.3 compact JSON plus LF, 347 bytes, SHA-256 `BFB97B3FF1BC13B36ED001D9CB26B2762D49C81F54A586464114272621DB5F18`; after G0 the first support mutation replaces it with the exact S6.4 object below, 343 bytes, SHA-256 `C69F59FF6AD09508D0253CD96D72B950F62B435E62C2BDB69AEBCC4DD4FD1552`.

## Outcome and acceptance

- Outcome: activate **Restore data backup** on Welcome and, only with a proven valid current generation and no active Restore or Erase intent, on `StartupMaintenanceView`; use the existing importer/validator to materialize a complete immutable generation from one validated schema-1 package, confirm it, install it, atomically switch canonical `current.json`, reopen and validate it, retire the old generation, regenerate pending PDFs, preserve failed Reports for explicit Retry, and rebuild the UI from the new session.
- Empty-install boundary: S6.4 may replace only a proven valid empty current generation. It does not union or replace existing customer records; current-data summary, `Back up current data`, `Replace current data`, and monotonic counted-root union begin only in S6.5. Cancel or ineligibility removes only the exact operation-owned stage and changes no pointer, generation, row, report, counter, or external package.
- Route truth: Welcome and eligible maintenance call the same importer/coordinator. Pointer-invalid, generation-missing, malformed/unknown Restore or Erase intent, an active Restore/Erase journal, or a nonempty current generation never enters the S6.4 mutation path. **Restore data backup** remains visually and semantically separate from **Restore Purchases**.
- Storage truth: before materializing the generation, perform overflow-safe important-usage capacity preflight on the actual target volume for twice `declaredPayloadByteCount` plus 20 percent plus the shared 64 MiB reserve. Failure creates no generation/journal/pointer mutation and leaves the prior generation readable.
- Materialization truth: copy only the closed-validated staged package into a fresh lowercase-UUID staging generation using exact schema-1 DTOs and unchanged media/snapshot/ready-PDF bytes. Create the SwiftData store with every frozen ID/value, require exact seven-model rows and relationships, require no extra bytes, and independently revalidate package, model, media, snapshot, Report, pack/template, counted-root, and pending/failed truth before installation.
- Journal truth: canonical `Application Support/FieldEvidenceRestore/restore.json` contains exactly `newGenerationID`, `newGenerationRelativePath`, `oldGenerationID`, `phase`, `restoreID`, `schemaVersion`, and `stagingGenerationRelativePath`; schema is 1 and phase is exactly `prepared|generation_installed|pointer_switched|new_generation_validated`. It is outside both old and new generation roots and is written/replaced atomically with no unknown field or phase.
- Phase truth: `prepared` means the complete staging generation is valid; `generation_installed` means those exact bytes were atomically renamed under `FieldEvidenceData/generations/` while old remains current; `pointer_switched` means canonical `current.json` names new and coordinator/root injection is rebuilding; `new_generation_validated` means the new current container reopened and every frozen ID/file/hash is readable, after which old enters canonical `retired.json` and exact stage/journal cleanup completes.
- Pointer/session truth: never rename, overwrite, or delete the active generation. Freeze old/new IDs and relative paths; use exact canonical `current.json`; activate the new `StoreSessionCoordinator` session only after pointer switch; increment its UI generation token once; and retire old only after the new current session passes full validation. Never infer newest directory or capture a permanent ModelContainer/context.
- Recovery ordering: restore reconciliation runs before ordinary pointer maintenance and before opening current. Unknown/malformed intent or impossible presence opens `restore_inconsistent` maintenance and deletes nothing. Every recovery revalidates exact directory identities, canonical bytes, expected pointer, and old/new generation authority before mutation.
- Presence matrix: at `prepared`, an installed new directory with old pointer is removed as proven uncommitted; otherwise stage/journal are removed and old remains. At `generation_installed`, old pointer plus valid new resumes switch, new pointer plus valid new advances, and invalid new leaves or atomically repoints old before removing only new. At `pointer_switched`, valid new remains and advances; invalid new atomically repoints old before removing new. At `new_generation_validated`, new must be current and valid, old is retired, and cleanup completes. Missing required old, a pointer naming neither frozen ID, an unexpected transition, unexpected owned bytes, or ambiguous authority enters maintenance without deletion.
- Report truth: after the new generation is active and validated, use the existing recovery/render path once. Pending Reports rerender idempotently; failed Reports remain failed until explicit Retry; ready Reports retain exact snapshot/PDF bytes and hashes. Restore never invents delivery readiness or rerenders failed authority.
- GOLDEN: both eligible routes call the same importer/coordinator; restore the checked-in mixed package with every exact ID/value/file/hash; canonical pointer names the validated new generation; old is retired; pending rerenders; failed remains failed; no Restore intent/stage remains; cold reopen validates the new generation; and the UI rebuilds from it at Accessibility XXXL with one terminal in-app screenshot.
- ALT-1: one bounded parameterized interruption family covers before/after each journal/filesystem/pointer/session boundary across all four phases and every required old/new/stage/pointer presence. Each case recovers to the prior valid generation or fully validated new generation, never deletes required old data, never adopts invalid/ambiguous new authority, and is idempotent on repeated launch.
- Accessibility/UI: reuse Worklight semantic components, logical focus/order, non-color progress/status, at least 44×44 controls, and every Dynamic Type category. Prevent duplicate import/install on double activation. Use only owner-frozen public action/fallback copy and existing system progress/error surfaces; do not invent a replacement-success, subscription, or destructive claim.
- Forbidden behavior: existing-data union/replacement; active-generation rename/delete; newest-directory guess; noncanonical pointer/journal; partial import; automatic repair/migration; failed-report automatic retry; Restore Purchases conflation; entitlement/diagnostic import; external package mutation; backend/cloud/account/sync; schema/model/project/capability/permission change; S6.5+ Settings replacement or S6.6 Erase behavior; signing, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s6-data-rights`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S6.4","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S6_4AtomicRestoreTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S6_4AtomicRestoreUITests"]}` plus exactly one LF; 343 UTF-8 bytes, no BOM; SHA-256 `C69F59FF6AD09508D0253CD96D72B950F62B435E62C2BDB69AEBCC4DD4FD1552`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before accepted S6.6 boundary integration, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Backup/RestoreIntentV1.swift`
- `FieldEvidenceApp/Infrastructure/Backup/RestoreIntentStore.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`

Test paths:

- `FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift`
- `FieldEvidenceAppUITests/S6_4AtomicRestoreUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, script, workflow, authority, or documentation path is allowed during S6.4 implementation. Existing S6.3 importer/validator/fixtures, canonical JSON, report/media/snapshot validators, generation pointer/session helpers, sign-pack registry, storage preflight, diagnostics, and design tokens may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s6-data-rights`, `A^=M`, exact one-commit HANDOFF-append-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins, accepted S6.3 exact-head run/artifact, accepted S6.3 selector byte-exact, and the ten-production/two-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S6.4 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S6.4 CI, read `KNOWN_BUGS.md`, append the immutable card HANDOFF, and—only if fresh refs still match—commit/push exactly that append plus immediate-next S6.5 `CURRENT_TASK.md`; then run fresh S6.5 G0. Do not mutate `main`.

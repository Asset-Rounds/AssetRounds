# Current Task

## Program and card

- Phase / branch / card / global order: `S3 / phase/s3-check-runner / S3.5 / 9 of 36`.
- Card heading: `### S3.5 — Low-storage and write-failure integrity`.
- Position / boundary / immediate next card: `5 of 7 / phase boundary no / S3.6`.
- Program autopilot / phase autopilot / exact S3 span / boundary integration: `enabled through accepted S9.1 / enabled / S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7 / yes at S3.7 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S3 phase-main base: `P=7d135aaddd0bdc50168552b0610f04adc1703506`.
- Accepted S3.4 integrated/card base: `M=E=I2=54aee71a6d824b8550af739ff538172dbf2d0a05`; initial I `759bb851dd6934b0c459d11e6dbb55f4abb595b7` failed exact run `31650093202`, and the accepted direct-child test correction changed only `FieldEvidenceAppTests/S3_4ResumeRecoveryTests.swift`; there was no distinct infrastructure verification head K.
- Predecessor exact-head evidence: run `31650769537`, job `94294400031`, succeeded at exact `phase/s3-check-runner@M` with P12/UI enabled; artifact `ios-ci-31650769537-1`, ID `9162697485`, size `1711727`, API/raw ZIP digest `sha256:1910e53b6a5dbf49d81957a6b3d238a0f7861021f4358aa748ff299167e484db`; `SHA256SUMS.txt` SHA-256 `348498572CF66CA26AC25FF6AE96A9DF1D8C391F863EFFE6134578DDFE0EF638`; all 103 payloads independently matched; `ui-final.png` SHA-256 `BDB2BF7772666D60CEC5C35B4AE4C40E856CEA1F77FEF43630EC45058A92142C`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `48/300` s, readiness `321/900` s, total `631/3300` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only `docs/execution/HANDOFF.md` S3.4 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s3-check-runner=M` and remote `main=P`; commit/push only the two authority paths, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S3.5 plan anchors: `## 10. Storage, crash consistency, and one-off bug prevention` (storage preflight, atomic evidence/snapshot publication, recovery truth); `## 12. Twelve must-pass launch smokes` (disk-full/write/interruption integrity); release-blocker anchors in `## 13`; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S3.4 LF SHA-256 `38EE4F0A75FD81EF6468907034757DEBD65ADA2B39A582CF46A52397DD1601CC`. Its first support mutation replaces it with the exact S3.5 object below, LF SHA-256 `6AE2565A4909BE28F616D0BA07DEEA6846E3D66D7432C48F9D3890EC6D75C0C7`.

## Outcome and acceptance

- Outcome: add bounded, instance-scoped injection seams for capacity preflight, atomic move/publication, snapshot operation, and SwiftData save failures so every active capture/finalization mutation either commits once or rolls back only its own new authority while every prior committed row/file remains readable.
- Injection posture: seams are inert by default, injectable only through explicit initializer dependencies or the exact test-only launch posture, scoped to one named operation/attempt, and removable for a later retry in the same test. No process-global mutable switch, production failure menu, generic mutation bus, job/recovery registry, or reusable fault framework is authorized.
- Capacity: important-usage capacity is checked on the actual generation volume before normalization, staging, row insertion, or draft-step mutation. Capacity unavailable or below the exact 68 MiB evidence estimate plus 64 MiB reserve produces no new row/file and leaves the draft retryable; a later sufficient-capacity retry succeeds.
- Evidence failure family: injected staging write or atomic staging-to-final move failure removes only the active mutation's proven staging/final bytes, creates no EvidenceFile row, does not advance the draft step, and preserves all previously accepted evidence. A database-save failure after active evidence promotion rolls back the model context and removes only that exact newly promoted owned bundle; cleanup mismatch fails closed rather than deleting unowned bytes. Removing the fault permits one successful retry.
- Finalization failure family: injected snapshot stage/write, snapshot promotion/move, intent phase write, or model save failure never changes prior committed records/evidence. Before database commit, cleanup is limited to the active frozen intent/stage/final artifacts whose exact ownership is proven and the draft remains retryable. A failure after the one database save uses the S3.4 journal/recovery matrix rather than deleting committed rows or guessing; replay/relaunch completes or exposes fail-closed maintenance from the frozen authority.
- GOLDEN: insufficient capacity blocks before every new row/file and leaves the same draft retryable; after capacity is restored, the exact retry succeeds once with prior committed authority unchanged.
- ALT-1: one parameterized family covers preflight, write, move, snapshot, intent-phase, and database-save interruption points; each fault rolls back only the active mutation or leaves an exact S3.4-recoverable journal state, every prior commit remains byte/readable-authoritative, and removing the fault permits one successful retry without duplicate/orphan rows or files.
- UI acceptance: the explicit test-only route exercises low-storage failure, visible actionable space-recovery copy, the existing Retry/import action, fault removal, and successful continuation with touched-control accessibility and one terminal screenshot. Production defaults expose no injection route or test copy.
- Forbidden behavior: fuzzing, endurance, exhaustive matrices, global/generalized fault framework, event log, repository/job/recovery registry, arbitrary filesystem interception, broad storage scan/cleanup, changes to the frozen S3.4 recovery matrix, PDF behavior, camera/permission/PhotosPicker, CNV, work, recheck, correction, deletion, backup/restore/erase, access/commerce, new model/schema/project/package/capability/permission/remote delta, or weakening any existing atomicity/ownership oracle.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s3-check-runner`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S3.5","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S3_5FailureIntegrityTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S3_5FailureRecoveryUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S3.6 transition only. Forbidden: force-push, merge/main mutation before S3.7, PR, ref rewrite/delete, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift`
- `FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`

Test paths:

- `FieldEvidenceAppTests/S3_5FailureIntegrityTests.swift`
- `FieldEvidenceAppUITests/S3_5FailureRecoveryUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

The existing Capture and Outcome/Review views already expose actionable failure copy and retry actions; S3.5 injects the exact test-only failure posture through existing app/shell/sign/coordinator ownership without editing or duplicating those views. No standalone failure fixture is required. `docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Fresh G0 proves `A^=M`; `M..A` is exactly one append-only HANDOFF plus CURRENT_TASK transition commit; remote main=P and remote phase=A; carried map/pins/public repository/environment/tool/method posture are byte-identical; selector remains accepted S3.4; no other path is dirty.
2. Replace selector first, implement only allowed paths, run structural/static Windows checks, explicitly stage task paths, and commit direct-child I.
3. Push exact phase ref non-force and run the one-at-a-time persistent P12 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/evidence artifacts; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
4. After accepted S3.5 evidence, append HANDOFF and transition only to immediate-next S3.6 when remote phase still equals accepted head. Do not mutate main.

## Definition of done

- Exact green S3.5 evidence proves capacity failure writes nothing, each bounded write/move/snapshot/database failure preserves prior commits and rolls back only the active owned mutation or leaves an exact S3.4-recoverable journal state, and fault removal permits one duplicate-free retry. Handoff records required evidence; remote phase equals accepted verification head, then continue only with S3.6.

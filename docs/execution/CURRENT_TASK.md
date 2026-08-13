# Current Task

## Program and card

- Phase / branch / card / global order: `S3 / phase/s3-check-runner / S3.6 / 10 of 36`.
- Card heading: `### S3.6 — Camera permission and denial recovery`.
- Position / boundary / immediate next card: `6 of 7 / phase boundary no / S3.7`.
- Program autopilot / phase autopilot / exact S3 span / boundary integration: `enabled through accepted S9.1 / enabled / S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7 / yes at S3.7 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S3 phase-main base: `P=7d135aaddd0bdc50168552b0610f04adc1703506`.
- Accepted S3.5 integrated/card base: `M=E=I2=3d082f530797262baf4964a349dfec0bed8c767f`; initial `I=127a6aef384850a6beaf315829ac8ad11aa839de` failed exact run `31652759185`, and the accepted direct-child correction changed only `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift` plus `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`; there was no distinct infrastructure verification head K.
- Predecessor exact-head evidence: run `31653492893`, job `94302688651`, succeeded at exact `phase/s3-check-runner@M` with P12/UI enabled; artifact `ios-ci-31653492893-1`, ID `9163673194`, size `1854311`, API/raw ZIP digest `sha256:b067792e9648208dcfe9db8321b6f0125e6409d670b147cc4940e15baa7c867e`; `SHA256SUMS.txt` SHA-256 `57BC79E58A3660B25230CAB8C2A7BEE6B9F00EB7925C4F8DF74F74291F83D5F4`; all 99 payloads independently matched; `ui-final.png` SHA-256 `30D9C814FAFE13DA7D46A8793C98D8D4B2D7EDD4CC93D67CC3D0CB79F9FA2F42`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `52/300` s, readiness `238/900` s, setup+artifact `54/300` s, total `634/3300` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only `docs/execution/HANDOFF.md` S3.5 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s3-check-runner=M` and remote `main=P`; commit/push only the two authority paths, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S3.6 plan anchors: `## 5. Navigation and onboarding` camera step and user-requested permission behavior; `## 6. Core workflow and state truth` safe incomplete route; `## 10. Storage, crash consistency, and one-off bug prevention` capture preflight; `## 13. Quality budget and known bugs` release-blocker and camera-denial recovery acceptance; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S3.5 LF SHA-256 `6AE2565A4909BE28F616D0BA07DEEA6846E3D66D7432C48F9D3890EC6D75C0C7`. Its first support mutation replaces it with the exact S3.6 object below, LF SHA-256 `FACE2CDEDF531B661F162DF130E9F08FBAE15F3C73B3E178727F732B45848826`.

## Outcome and acceptance

- Outcome: add a user-requested camera adapter at the existing wide/close capture actions. Permission is queried/requested only after the user chooses camera, never at app launch, preflight, draft creation, relaunch, or Photos import. Authorized capture and deterministic authorized test-adapter bytes enter the existing S3.2 normalizer/stage/accept pipeline; no second media authority path is permitted.
- Exact project delta: add only `NSCameraUsageDescription = Use the camera to add sign photos to reports stored on this iPhone.` to the app target's generated Info.plist settings, consistently for Debug and Release. No photo-library, location, microphone, contacts, or other usage key/capability/entitlement is allowed.
- Capture controls: each wide/close step offers `Take photo`, `Choose from Photos`, and `Cannot complete`; the existing Retake/Use Photo and preview remain the only candidate acceptance controls. PhotosPicker uses item-only access and must not request broad photo-library permission. Camera output and PhotosPicker output both pass as source bytes through the existing capacity gate, canonical JPEG normalizer, staging, preview, promotion, and one EvidenceFile/step save.
- Permission state: `.notDetermined` requests authorization only from the explicit Take photo action; `.authorized` presents capture; `.denied` or `.restricted` exposes actionable `Choose from Photos`, `Open Settings`, and `Cannot complete` without repeatedly prompting. Returning from Settings rechecks status. Camera unavailable or capture cancellation/failure preserves the current draft/step/evidence and keeps alternate actions available.
- Safe incomplete boundary: `Cannot complete` is a resumable exit from capture in S3.6: it strands no draft and mutates no outcome, CNV reason, Report, Packet, Issue, snapshot, or finalization authority. S3.7 alone activates the post-draft Could-not-verify choice and persisted `capture_unavailable` result; until then the user can return to the same active draft/step and choose camera or Photos.
- GOLDEN: an explicitly authorized deterministic fixture adapter returns wide and close source bytes through the existing normalizer and produces the same canonical original/thumbnail EvidenceFile authority as imported capture, with no launch permission request and no bypass of storage/media ownership.
- ALT-1: a parameterized not-determined→denied, already-denied, restricted, unavailable, cancellation, and Settings-return family always offers PhotosPicker or Settings plus the safe resumable incomplete exit, never loops permission, mutates draft progress without accepted evidence, or strands the draft.
- UI acceptance: the exact UI test uses explicit test-only injected permission/capture states, verifies no launch prompt, user-triggered request, denial recovery controls and touched-control accessibility, chooses Photos or the deterministic authorized adapter to complete wide/close, and retains one terminal screenshot. Production defaults expose no fixture route, test state menu, or test copy.
- Forbidden behavior: launch/preflight permission prompt, broad photo-library authorization, PHPicker/UIImagePicker library fallback that requests library permission, production fixture route, camera quality/low-light claim, custom camera library, live-photo/video/audio/location capture, CNV persistence/finalization, outcome expansion, new model/schema, generalized permission service/registry, unrelated view redesign, PDF, work/recheck, deletion/backup/restore, access/commerce, package/capability/entitlement/remote delta, or any S3.7+ behavior.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s3-check-runner`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S3.6","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S3_6CameraRecoveryTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S3_6CameraRecoveryUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S3.7 transition only. Forbidden: force-push, merge/main mutation before S3.7, PR, ref rewrite/delete, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp.xcodeproj/project.pbxproj`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Features/CheckRunner/PreflightView.swift`
- `FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift`
- `FieldEvidenceApp/Features/CheckRunner/CameraCaptureView.swift`
- `FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift`

Test paths:

- `FieldEvidenceAppTests/S3_6CameraRecoveryTests.swift`
- `FieldEvidenceAppUITests/S3_6CameraRecoveryUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

The existing `CheckRunnerCoordinator.importCandidate` and S3.2 media pipeline consume camera/Photos source bytes unchanged, so coordinator/media/storage/finalization/model edits are neither needed nor authorized. App→Shell→Signs→Preflight carries only explicit camera-adapter/test posture into the existing Capture screen. `CameraCaptureView.swift` is the minimal system camera presentation wrapper; `CameraAdapter.swift` owns permission/status/request and deterministic test dependency contracts. The existing S3.2 checked-in wide/close UI fixture bytes may be reused by the exact test-only posture without changing fixture files. `docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Fresh G0 proves `A^=M`; `M..A` is exactly one append-only HANDOFF plus CURRENT_TASK transition commit; remote main=P and remote phase=A; carried map/pins/public repository/environment/tool/method posture are byte-identical; selector remains accepted S3.5; no other path is dirty.
2. Replace selector first, implement only the exact allowed paths, run structural/static Windows checks, explicitly stage task paths, and commit direct-child I.
3. Push exact phase ref non-force and run the one-at-a-time persistent P12 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/evidence artifacts; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
4. After accepted S3.6 evidence, append HANDOFF and transition only to immediate-next S3.7 when remote phase still equals accepted head. Do not mutate main.

## Definition of done

- Exact green S3.6 evidence proves no launch prompt; explicit camera action owns the permission request; authorized adapter and PhotosPicker source bytes use the existing normalizer/atomic acceptance pipeline; denial/restriction/unavailability/cancel offer Photos or Settings plus a safe resumable exit without draft/evidence mutation; exact camera usage copy is the sole project permission delta. Handoff records required evidence; remote phase equals accepted verification head, then continue only with S3.7.

# Current Task

## Program and card

- Phase / branch / card / global order: `S3 / phase/s3-check-runner / S3.3 / 7 of 36`.
- Card heading: `### S3.3 — Outcome, review, recoverable finalization, and snapshot`.
- Position / boundary / immediate next card: `3 of 7 / phase boundary no / S3.4`.
- Program autopilot / phase autopilot / exact S3 span / boundary integration: `enabled through accepted S9.1 / enabled / S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7 / yes at S3.7 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S3 phase-main base: `P=7d135aaddd0bdc50168552b0610f04adc1703506`.
- Accepted S3.2 integrated/card base: `M=E=I3=0dae8c52dcfcbf8a2ad17c739bd0bb2d6b7b43ce`; initial `I=f1562c7718da6d3cb835315dbf21493ae17af086`; `I2=0cca7efd97940a06e5ecdd269b3e483b7113be3f`; I2 changed only the normalizer and its unit test for the Xcode 26 `copyICCData()` API spelling; I3 changed only `PreflightView.swift` so the capture root accessibility identifier is not masked.
- Predecessor exact-head evidence: run `31643819476`, job `94272573406`, succeeded at exact `phase/s3-check-runner@M` with P12/UI enabled; artifact `ios-ci-31643819476-1`, ID `9160153393`, API/raw ZIP digest `sha256:ebf1a91d2ae0c4de18061255ea6fa43a65fdaed772d37c6a9860ce4112791660`; `SHA256SUMS.txt` SHA-256 `B89B1CCF6B93ACB621B133834E3EA0AF7B7A72587F7EA38FBABBF37A82EDF2D6`; all 101 payloads independently matched; `ui-final.png` SHA-256 `0FA105A007AC7A2F9119DA827B872C59B614AED49AEACA7F163C018300A20E93`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `48/300` s, readiness `128/900` s, setup+artifact `50/300` s, total `515/3300` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only `docs/execution/HANDOFF.md` S3.2 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s3-check-runner=M` and remote `main=P`; commit/push only the two authority paths, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S3.3 plan anchors: `## 6. Core workflow and state truth`; `## 9. Smallest reusable architecture` (`Persistent models`, exact `ReportSnapshotV1`); `## 10. Storage, crash consistency, and one-off bug prevention` (`FinalizationIntentV1`). Global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S3.2 LF SHA-256 `B2C7E95F27D48E717C503AF95A128EBA9E4E986ECD6A58B619A9BB635B025296`. Its first support mutation replaces it with the exact S3.3 object below, LF SHA-256 `567B68707B18B9A9CC719CB4A176CF60B8184F94E0EF70740B03E18FDADCE7DA`.

## Outcome and acceptance

- Outcome: replace the S3.2 terminal placeholder with Outcome and Review for the existing original check draft, then perform one journaled finalization that creates exactly one completed WorkflowRecord, optional Issue, Packet/root, canonical immutable snapshot, pending Report, and one shared Value receipt presentation. PDF rendering, report detail, and sharing remain unavailable.
- Outcome choices: `no_visible_issue` and `visible_issue` only. Visible issue requires exactly one closed sign-pack issue label and freezes both its key and display into one newly opened Issue; no-visible-issue creates none. S3.7 owns `could_not_verify`; S5 owns work/recheck outcomes.
- Review: show the selected outcome, selected issue label when applicable, accepted wide/close evidence, frozen preflight time/acknowledgement facts, and one explicit Save/Finish action. Back may revise the uncommitted choice; finalization starts only from Review and disables duplicate submission while active.
- Snapshot: encode the exact plan `ReportSnapshotV1` closed DTO and nested DTOs. Top-level arrays are never null; acknowledgement order is `[after_dark,safe_authorized_position]`; effective evidence source is `sourceRecord.evidenceSourceRecordID ?? sourceRecord.id`; current evidence is only that record's exact immutable wide/close rows, in purpose/UUID order, with both original and thumbnail facts and frozen purpose displays. Original check history/issues are empty except the optional newly opened current Issue. Freeze exact pack, PDF-template, source-app, Site/Asset, time, acknowledgement, stage/outcome display, note/null, disclaimer, packet/root/report/record IDs and instants.
- Canonical bytes: UTF-8/NFC, LF, no BOM/indent/trailing whitespace/newline, lexicographically sorted keys at every level, unescaped `/`, JSON-required escaping only, lowercase UUID/hash, RFC3339 UTC with exactly three fractional digits and `Z`, explicit nulls, integer/bool JSON forms, no floats. The checked-in golden JSON plus expected SHA-256 is encoder authority; the digest covers exact snapshot bytes and is stored only on Report.
- Finalization intent: canonical `FinalizationIntentV1` lives at `Application Support/FieldEvidenceOperations/finalization/<mutation-id>.json`, uses exactly the plan's 15 keys and phase `prepared|snapshot_promoted|database_committed`; `FinalizationPayloadV1` uses exactly `issueInsert`, `issueTransition`, `packetAfter`, `packetBefore`, `reportInsert`, and `workflowRecordAfter` with explicit nulls. Validate the injected generation root is exactly `FieldEvidenceData/generations/<generation-id>` before deriving the sibling operations root; never guess a generation or escape either root.
- Ordered mutation: freeze one mutation ID, all IDs/instants/payload and snapshot; write/verify staged snapshot plus hashes; atomically write `prepared`; atomically promote identical bytes to `snapshots/<report-id>.json`; atomically advance `snapshot_promoted`; verify frozen Packet/Issue preconditions; perform one SwiftData save for the completed record, optional Issue, Packet, and pending Report; advance `database_committed`; remove only matching staging/intent. A save/precondition failure removes only the intent-owned promoted snapshot/intent and leaves the draft retryable. Do not implement the S3.4 relaunch phase/presence recovery matrix or S3.5 injection framework.
- GOLDEN: No visible issue creates exactly one completed original check and one live Packet whose `stableRootID` is immutable and whose `currentRecordID` is that record; one pending Report has null PDF path/hash and points to a durable canonical snapshot promoted before the row save. Exact effective-source/stage/display/original+thumbnail snapshot bytes match the checked-in fixture and digest. One Value receipt is actually presented; View Report and Share are visibly unavailable. Attempt `report_saved` only after the Report exists, and installation-first `onboarding_completed` only when that Value receipt is actually presented; diagnostic persistence is non-authoritative and cannot roll back product success.
- ALT-1: Visible issue cannot proceed without one valid closed label; with one selected it creates exactly one linked open Issue using the frozen key/display and sets the completed record's `issueID` to it, while retaining the same one-record/one-packet/one-report/snapshot/receipt guarantees.
- Forbidden behavior: PDF bytes/renderer/retry/detail/preview/share/export/delivery receipt; second receipt type; CNV, work, recheck, correction, deletion, backup, restore, access/paywall/StoreKit; finalization recovery matrix/startup reconciliation/fault-injection framework; generic mutation bus/repository/job/schema registry; new model/schema/project/package/capability/permission/remote delta.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s3-check-runner`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S3.3","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S3_3FinalizationTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S3_3GoldenCheckUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S3.4 transition only. Forbidden: force-push, merge/main mutation before S3.7, PR, ref rewrite/delete, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Workflow/FinalizationContracts.swift`
- `FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift`
- `FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift`
- `FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift`

Test paths:

- `FieldEvidenceAppTests/S3_3FinalizationTests.swift`
- `FieldEvidenceAppTests/Fixtures/S3_3ReportSnapshotV1.json`
- `FieldEvidenceAppTests/Fixtures/S3_3ReportSnapshotV1.sha256`
- `FieldEvidenceAppUITests/S3_3GoldenCheckUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Fresh G0 proves `A^=M`; `M..A` is exactly one append-only HANDOFF plus CURRENT_TASK transition commit; remote main=P and remote phase=A; carried map/pins/public repository/environment/tool/method posture are byte-identical; selector remains accepted S3.2; no other path is dirty.
2. Replace selector first, implement only allowed paths, run structural/static Windows checks, explicitly stage task paths, and commit direct-child I.
3. Push exact phase ref non-force and run the one-at-a-time persistent F25 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/evidence artifacts; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
4. After accepted S3.3 evidence, append HANDOFF and transition only to immediate-next S3.4 when remote phase still equals accepted head. Do not mutate main.

## Definition of done

- Exact green S3.3 evidence: both outcome branches enforce their closed inputs; finalization promotes one exact canonical snapshot before one atomic model save; no-visible creates no Issue and visible creates exactly one linked Issue; one completed record/Packet/root/pending Report and one presented shared receipt survive the tested completion flow; diagnostics are attempted at their exact post-authority/presentation points; View Report/Share and all adjacent future behavior remain absent.
- Handoff records required evidence; remote phase equals accepted verification head, then continue only with S3.4.

# Current Task

## Program and card

- Phase / branch / card / global order: `S3 / phase/s3-check-runner / S3.7 / 11 of 36`.
- Card heading: `### S3.7 — Post-draft Could-not-verify`.
- Position / boundary / immediate next card: `7 of 7 / phase boundary yes / S4.1`.
- Program autopilot / phase autopilot / exact S3 span / boundary integration: `enabled through accepted S9.1 / enabled / S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7 / yes`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S3 phase-main base: `P=7d135aaddd0bdc50168552b0610f04adc1703506`.
- Accepted S3.6 integrated/card base: `M=E=I=86fd3a3576cd77889c15a0f6501deb55a33fb9c1`; there was no correction and no distinct infrastructure verification head K.
- Predecessor exact-head evidence: run `31655122900`, job `94307810126`, succeeded at exact `phase/s3-check-runner@M` with P12/UI enabled; artifact `ios-ci-31655122900-1`, ID `9164240287`, size `1994434`, API/raw ZIP digest `sha256:0bee4c34b100eb58f8dea90c14e58403d5c1b8f4ab746a02551607558835ecbe`; `SHA256SUMS.txt` SHA-256 `DFDD1067F25C743D12D51F38992B897B0C63BE9980D3E53CD6B297622131C40B`; all 95 payloads independently matched; `ui-final.png` SHA-256 `184071D46E24E86CB28EF2B93FEDC70A0DD2FAE978813D2E661D8240787FAF1C`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `30/300` s, readiness `150/900` s, setup+artifact `30/300` s, total `498/3300` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only `docs/execution/HANDOFF.md` S3.6 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s3-check-runner=M` and remote `main=P`; commit/push only the two authority paths, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S3.7 plan anchors: `## 6. Core workflow and state truth` exact post-draft CNV effects; `## 7. Report truth and deterministic delivery` incomplete evidence truth; `## 8. Content-pack contract` exact CNV registry and accepted-evidence cardinality; `## 10. Storage, crash consistency, and one-off bug prevention` ordered recoverable finalization; `## 13. Quality budget and known bugs` CNV release-blocker acceptance; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S3.6 LF SHA-256 `FACE2CDEDF531B661F162DF130E9F08FBAE15F3C73B3E178727F732B45848826`. Its first support mutation replaces it with the exact S3.7 object below, LF SHA-256 `57C8276ED267CCA525C924A5189FB93C09AB0CDA7D0AC8509F7768CB1F242AD0`.

## Outcome and acceptance

- Outcome: after Begin check has durably created the draft, `Cannot complete` opens the bounded Could-not-verify flow without deleting or substituting accepted evidence. A closed reason plus exact display/version and an optional trimmed note finalizes one honest incomplete original check/root/Packet/pending Report/canonical snapshot through the existing S3.3–S3.5 atomic service.
- Closed truth: outcome is exactly `could_not_verify`; `couldNotVerifyKey`, `couldNotVerifyDisplaySnapshot`, and `couldNotVerifyRegistryVersion` are all nonnull together, frozen from the unique bundled `cnv.reason.en-US.v1` entry, and remain null for non-CNV outcomes. The optional note is trimmed, null when empty, and 1–1000 characters when present.
- Closed registry order/copy: `conditions_changed` → `Conditions changed`; `access_lost` → `I lost safe access`; `unsafe_to_continue` → `It became unsafe to continue`; `required_view_obstructed` → `Required view is blocked`; `capture_unavailable` → `Camera or photo capture is unavailable`; `other` → `Another reason`. Unknown, duplicate, reordered, or stale-version selection fails closed.
- Evidence truth: CNV permits zero or one existing `wide_context` and zero or one existing `close_detail`, never duplicates or `work_context`; it preserves every accepted canonical EvidenceFile byte/row, labels each missing required purpose as not captured/incomplete in the review/snapshot truth, and never fabricates, substitutes, promotes, or deletes evidence.
- Finalization effects: create no Issue, pass, resolution, accepted-result claim, or separate billing/analytics event. Create exactly one completed original check, one live Packet/root with `evaluationCounted=true`, one pending Report, one durable canonical snapshot, and the existing post-Report `report_saved` diagnostic/Value receipt. Retry/relaunch stays duplicate-free under the existing intent phases, replay, rollback, and S3.4 startup recovery.
- GOLDEN: one accepted wide photo plus `required_view_obstructed` and an optional note produces one honest incomplete snapshot/Report/root, retains that exact wide evidence, records close as missing, carries exact CNV fields, and creates no Issue.
- ALT-1: zero-photo `capture_unavailable` produces the same honest incomplete authority shape with both required purposes missing, no EvidenceFile mutation, and no Issue/pass/resolution.
- UI acceptance: the exact UI test begins a real draft, accepts one wide fixture through the existing media path, chooses Cannot complete, selects the closed reason, reviews retained-wide/missing-close truth, saves, relaunches without duplicate authority, and retains one terminal Value-receipt screenshot. The zero-photo family is unit-covered. Every reason, note, Continue/Save/Back, missing-purpose label, and receipt control is accessible and actionable.
- Forbidden behavior: pre-draft CNV, CNV from Cancel, default/new Issue, pass/resolution wording, evaluation-credit bypass or extra root, evidence requirement weakening for substantive no-visible/visible outcomes, evidence duplication/substitution/deletion, new model/schema/registry/service, production fixture route, camera/permission/media-policy change, PDF generation/rendering, work/recheck, report detail/share/export, deletion/backup/restore, access/commerce, package/project/capability/entitlement/remote delta, or any S4.1+ behavior.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s3-check-runner`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S3.7","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S3_7CouldNotVerifyTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S3_7CouldNotVerifyUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, append HANDOFF and execute the ordered boundary state machine below. Forbidden: force-push, merge commit, PR, ref rewrite/delete, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift`
- `FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`

Test paths:

- `FieldEvidenceAppTests/S3_7CouldNotVerifyTests.swift`
- `FieldEvidenceAppUITests/S3_7CouldNotVerifyUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

The existing `CaptureStepView` already owns the post-draft Cannot-complete control and can present the existing Outcome/Review surface without App/Shell/Signs/Preflight wiring changes. `CheckRunnerCoordinator` owns unique pack-registry resolution, partial-evidence review, retry identity, and the exact service input. `FinalizationService` owns closed CNV/evidence validation plus frozen WorkflowRecord/payload/snapshot fields while preserving the existing atomic journal/model-save/replay contract; `FinalizationRecoveryService` validates and completes the same frozen CNV payload/snapshot after a post-save interruption without guessing or weakening its zero/one-evidence authority. Existing `WorkflowRecord`, `FinalizationContracts`, `ReportSnapshotV1`, `ReportSnapshotEncoderV1`, intent store, sign pack, media stores, diagnostics, Value receipt, project, resources, and fixtures already contain the required generic fields/contracts and are not authorized to change. `docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Fresh G0 proves `A^=M`; `M..A` is exactly one append-only HANDOFF plus CURRENT_TASK transition commit; remote main=P and remote phase=A; carried map/pins/public repository/environment/tool/method posture are byte-identical; selector remains accepted S3.6; no other path is dirty.
2. Replace selector first, implement only the exact allowed paths, run structural/static Windows checks, explicitly stage task paths, and commit direct-child I.
3. Push exact phase ref non-force and run the one-at-a-time persistent P12 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/evidence artifacts; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
4. After accepted S3.7 evidence, re-fetch and append the complete S3.7 HANDOFF only; commit/push its phase-close head C, leaving product bytes equal to accepted E. Verify the phase ref at exact C with UI-enabled CI before any main mutation.
5. After green exact phase-close C evidence, re-fetch and prove `origin/main=P` plus C descends from P; non-force fast-forward main to the exact accepted phase-close/verification head and run exact-main UI-enabled CI. No next-phase branch or task may start before that exact-main candidate is green with complete evidence.
6. Only after green exact-main evidence, create or non-force fast-forward `phase/s4-reports` from that exact green main head, hydrate only immediate-next S4.1 CURRENT_TASK with accepted integration evidence, commit/push that authority, and run fresh S4.1 G0. Never force, merge, or pre-implement S4.1.

## Definition of done

- Exact green S3.7 evidence proves the one-wide GOLDEN and zero-photo ALT-1 honest incomplete shapes; exact closed CNV fields/note/evidence truth; one counted root/Packet/pending Report/canonical snapshot; zero Issue/pass/resolution/extra credit; duplicate-free retry/relaunch; and accessible receipt. The S3 phase closes only after ordered green phase-close and exact-main verification; then continue only with S4.1 on `phase/s4-reports` from that exact green main head.

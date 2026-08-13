# Current Task

## Program and card

- Phase / branch / card / global order: `S4 / phase/s4-reports / S4.2 / 13 of 36`.
- Card heading: `### S4.2 — PDF failure, relaunch reconciliation, and Retry`.
- Position / boundary / immediate next card: `2 of 5 / phase boundary no / S4.3`.
- Program autopilot / phase autopilot / exact S4 span / boundary integration: `enabled through accepted S9.1 / enabled / S4.1,S4.2,S4.3,S4.4,S4.5 / yes at S4.5 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S4 phase-main base: `P=8b33ee6a26ed4f7ccdccc8e092920b26c6e04122`.
- Accepted S4.1 integrated/card base and product implementation: `M=E=I5=2dec12bb4d1992a4c160b3b357dc95d6118d4ae9`; implementation sequence `I=6486abdf9bad8b6be4edde5147461e030384cdb1`, `I2=0c3ff1db26ca207df7a91fc266d43fc0763ae8ed`, `I3=c0b41e8fdcee2140a1c3b27fddcbcb82dc3b1553`, `I4=f4da51b305af6c822649534b24a1fad81773120d`, then accepted I5. No distinct infrastructure verification head K exists.
- Predecessor exact-head evidence: run `31664479971`, job `94335997292`, succeeded at exact `phase/s4-reports@M` with N8/UI disabled; artifact `ios-ci-31664479971-1`, ID `9167473413`, size `265138`, API/raw ZIP digest `sha256:8902cace16f6dacc4fb691a9ef8d6e3d3eb37f7863850b3c285e9b8a334895c4`; `SHA256SUMS.txt` SHA-256 `DD5394938069822C426D3B8EAD07A92F03FCFAD7BF48842BC4D74D1DE41B0B6F`; all `61/61` payloads independently matched. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `22/300` s, readiness `193/900` s, build `101/600` s, unit `51/900` s, setup+artifact `26/300` s, total `274/2400` s. UI execution, selector, result bundle, log, and screenshot were absent exactly as N8 requires.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only `docs/execution/HANDOFF.md` S4.1 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s4-reports=M` and remote `main=P`; commit/push only the two authority paths, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S4.2 plan anchors: `## 6. Core workflow and state truth` Report truth; `## 9. Smallest reusable architecture` persistent Report delivery-state authority and retained V1 renderer; `## 10. Storage, crash consistency, and one-off bug prevention` PDF preflight/promotion/startup rules; `## 13. Quality budget and known bugs` report loss/corruption/false-success release blockers; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S4.1 LF SHA-256 `0637239D84BE60B3D7B158ED21B1B2CA0D1C198160B8405B246CB143838A5C5D`. Its first support mutation replaces it with the exact S4.2 object below, LF SHA-256 `4BF3B5D8947F11D5D248258FA9B7F63F577181CAFA325B851AECDC63C94CC2AA`.

## Outcome and acceptance

- Outcome: activate the reserved PDF startup checkpoint and one bounded `ReportRecoveryService` so renderer/preflight/write/save failures preserve the completed record and immutable canonical snapshot, pending/failed relaunch state reconciles only its exact report-ID-owned files, and the user can explicitly run one `Retry report` attempt. No automatic retry loop, replacement Report, or snapshot/evidence mutation exists.
- Delivery-state authority: legal transitions are only `pending→ready|failed`, explicit user-triggered `failed→pending`, then `pending→ready|failed`; `ready` is terminal. `pending` and `failed` require nil `pdfRelativePath`/`pdfSHA256`; `ready` requires exact canonical `pdfs/<lowercase-report-id>.pdf`, lowercase SHA-256, and matching regular nonsymlink bytes. Source, snapshot, packet, report identity/creation/replacement, evidence, evaluation count, and diagnostics authority never change during rendering or Retry.
- Failure boundary: after proving and removing only the active Report's exact owned stage/final artifacts, a validator, capacity, render, stage/write, promotion, reread/hash, or ready-save failure rolls back the active delivery mutation and durably changes only that pending Report to failed with nil PDF fields. Failure to prove ownership, remove an owned artifact, roll back, or persist the failed state is not shown as safely retryable; it fails closed through the existing startup maintenance route without adding or naming a new maintenance-reason enum case and without mutating unrelated authority.
- Startup ordering and bounded pass: after current-generation open, exact finalization recovery, the reserved deletion checkpoint, and media reconciliation, activate the existing `.pdf` checkpoint before feature writes. Validate every Report row's state/nullability and exact report-ID path authority first. Process each valid pending Report at most once in that launch pass with the retained snapshot-stored V1 template renderer; valid failed Reports are never rendered at launch and remain failed until explicit Retry. There is no timer, recursive call, background worker, queue, job registry, or process-global retry switch.
- Presence reconciliation: a ready row is accepted unchanged only when its expected stage is absent and its exact final path/hash/regular nonsymlink bytes all match; a missing/mismatched ready final, noncanonical row path/hash, unexpected type/symlink, or stage beside a ready final fails closed through the existing maintenance route because ready is terminal and cannot be regenerated or demoted. For pending/failed rows with nil PDF fields, inspect only `.staging/pdfs/<lowercase-report-id>.pdf` and `pdfs/<lowercase-report-id>.pdf`; remove an exact regular nonsymlink non-ready artifact only after proving its deterministic report-ID-owned path. Simultaneous stage and final, or any unsafe/unexpected type/path/symlink, fails closed through existing maintenance. After cleanup, failed remains failed; pending performs one fresh deterministic render/promotion/verification attempt and becomes ready only from matching regenerated bytes/hash, otherwise failed/retryable. Never scan, delete by age, follow a link, adopt an unverified file, or touch an unowned path.
- Explicit Retry: the one primary `Retry report` action first persists exactly `failed→pending` with unchanged nil PDF fields and unchanged immutable authority, then invokes one render attempt. Success uses the S4.1 preflight/stage/atomic-promotion/reread/save path and becomes ready; failure cleans only proven owned output and returns to failed. Repeated taps are disabled while the attempt runs, a failed transition/save stays failed, and no Retry increments `report_saved`, onboarding, share, billing, or evaluation authority.
- GOLDEN: an injected one-attempt render failure on a pending Report produces exactly one failed row with nil PDF fields, no stage/final PDF, and byte-identical source/snapshot/evidence authority. After the fault is removed, one explicit Retry performs `failed→pending→ready` on the same Report and snapshot, yielding the exact S4.1 canonical path, deterministic PDF bytes, and hash with no duplicate row/file/counter.
- ALT-1: the bounded interrupted-promotion/relaunch family covers absent, expected stage-only, expected final-only, and ready-final presence. Startup removes only exact owned non-ready artifacts; pending rerenders once and reaches ready only after exact path/hash/byte verification, failed remains failed/retryable without automatic rendering, and a valid ready row remains byte-identical. Unsafe, simultaneous, malformed, missing-ready, or mismatched-ready authority reaches existing maintenance without replacement, demotion, broad cleanup, or guess.
- UI acceptance: the exact UI test creates one pending Report through the existing imported-fixture check path, relaunches with the inert-by-default one-shot S4.2 render-failure launch posture, observes honest retained-record/non-delivery state and the exact `Retry report` control, removes or consumes the fault, retries once to ready, and relaunches without duplicate authority or another automatic attempt. The failure headline receives focus on entry or repeated failure; the primary action has a label, button trait, logical order, non-color state, 44-point target, disabled in-progress state, and deterministic focus return. Keep one terminal in-app screenshot; no report preview/detail/share claim is shown.
- Negative family: unknown PDF state, invalid state/path/hash nullability, duplicate/colliding Report authority, noncanonical path/hash, unsafe directory/symlink/special file, simultaneous stage/final, missing or mismatched ready bytes, ambiguous ownership, cleanup/rollback/save failure, or invalid generation fails closed without changing source/snapshot/evidence or claiming ready. An ordinary proven-owned render fault becomes failed/retryable, never a completed-record rollback or replacement.
- Forbidden behavior: automatic/periodic/background retry; more than one render attempt per launch or tap; direct `failed→ready`; any `ready` mutation/regeneration; replacement Report/snapshot/evidence/Packet/root; broad filesystem scan, age cleanup, link following, or unowned deletion; generic job/recovery registry, event log, mutation bus, process-global production fault switch, new maintenance-reason enum case, new schema/model/project/package/capability/permission/remote change; S4.3 detail/preview/Share/Files/Value-receipt activation; S4.4 index/filter/history/comparison; S4.5 correction; renderer/template/validator/storage-contract changes; camera/media/finalization/work/recheck/deletion/backup/restore/access/commerce; or any later-phase behavior.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s4-reports`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S4.2","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S4_2PDFRecoveryTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S4_2PDFRetryUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S4.3 transition only. Forbidden: force-push, merge/main mutation before S4.5, PR, ref rewrite/delete, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`
- `FieldEvidenceApp/Features/Reports/ReportFailureView.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift`

Test paths:

- `FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift`
- `FieldEvidenceAppUITests/S4_2PDFRetryUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`ReportRenderService` owns the bounded delivery transition and inert injectable one-attempt render fault. New `ReportRecoveryService` owns the exact row/stage/final startup matrix and explicit Retry operation. `StartupRouter` activates only its already-reserved PDF checkpoint and existing closed maintenance/retryable routes; the app root wires the single new failure view and test-only launch posture. Synchronized source groups include the two new Swift paths; the unit fixture is synthesized in its single test file and the UI test reuses existing imported media, so no project/resource/fixture delta is needed. Existing `Report`, `ReportPDFState`, `SnapshotValidatorV1`, `WorklightPDFRendererV1`, `StoragePreflightService`, finalization/snapshot/evidence authority, Value receipt, AppShell/Signs/CheckRunner routes, diagnostics, S4.1 tests, project, and closed maintenance-reason set remain unchanged. `docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Fresh G0 proves `A^=M`; `M..A` is exactly one append-only HANDOFF plus CURRENT_TASK transition commit; remote `main=P` and remote `phase/s4-reports=A`; accepted S4.1 exact-head evidence is complete; carried map/pins/public repository/environment/tool/method posture is byte-identical; selector remains accepted S4.1; no other path is dirty.
2. Replace selector first, implement only the exact allowed paths, run structural/static Windows checks without claiming an iOS build, explicitly stage task paths, and commit direct-child I.
3. Push exact phase ref non-force and run the one-at-a-time persistent P12 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/evidence artifacts; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
4. After accepted S4.2 evidence, re-fetch and append the complete S4.2 HANDOFF plus hydrate only immediate-next S4.3 CURRENT_TASK in one direct-child same-phase authority commit; keep `main=P`, push non-force, and require fresh S4.3 G0 before any S4.3 implementation.

## Definition of done

- Exact green S4.2 evidence proves pending failure preserves the immutable completed record/snapshot/evidence, creates one failed/nil-PDF state with no orphan, explicit Retry alone performs one `failed→pending→ready|failed` attempt, crash-window startup cleanup touches only exact owned paths, valid ready authority is immutable, invalid/unsafe authority fails closed through existing maintenance, failed never auto-renders, and the accessible one-failure view makes no false ready/delivery claim. Handoff records complete evidence; remote phase equals accepted verification head, then continue only with S4.3 after the exact same-phase authority transition and fresh G0.

# Current Task

## Program and card

- Phase / branch / card / global order: `S4 / phase/s4-reports / S4.3 / 14 of 36`.
- Card heading: `### S4.3 — Value receipt, detail, preview, Share, and Files`.
- Position / boundary / immediate next card: `3 of 5 / phase boundary no / S4.4`.
- Program autopilot / phase autopilot / exact S4 span / boundary integration: `enabled through accepted S9.1 / enabled / S4.1,S4.2,S4.3,S4.4,S4.5 / yes at S4.5 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S4 phase-main base: `P=8b33ee6a26ed4f7ccdccc8e092920b26c6e04122`; remote `main` must remain exactly P through S4.4.
- Accepted S4.2 integrated/card base and product implementation: `M=E=I3=acdb3248c8ced353cb1d706663e9232b5332fa9f`; implementation sequence `I=357fd3e7b527a67c1eae6e4d8534f19633ec315e`, `I2=834e3f1a7a70721524023ce250a43ff5553f48ca`, then accepted I3. No distinct infrastructure verification head K exists.
- Predecessor exact-head evidence: run `31669480211`, job `94350970095`, succeeded at exact `phase/s4-reports@M` with P12/UI enabled; artifact `ios-ci-31669480211-1`, ID `9169273770`, size `1820138`, API/raw ZIP digest `sha256:eee032a892f423335c16c441727aba56beff528e886fdb8ea52a1e63b89c80e3`; `SHA256SUMS.txt` SHA-256 `FAC3FA06D072910967042BB33EA0602E5B508FE4B3F4B3450318EDF3FF4233D1`; all `107/107` payloads independently matched; `ui-final.png` SHA-256 `D6A1AC934C3B09BD0F95673F71103D4B9E0EAE8C0E0D5C6E9531E96F29198E92`.
- Predecessor runner/toolchain/destination/budgets: `macos26` image `20260728.0273.1`; Xcode 26.6 `17F113`; iPhone 17 / iOS 26.5 build `23F77` / UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `15/300` s, readiness `141/900` s, build `98/600` s, unit `58/900` s, UI `149/900` s, total `370/3300` s; `8/8` unit and `1/1` UI tests passed.
- Task-start authority head A is the direct-child S4.2→S4.3 transition commit observed after that commit exists at fresh G0; this pre-commit authority file deliberately never self-records A's future SHA.
- Required `M..A`: exactly one direct-child same-phase transition commit changing only the append-only `docs/execution/HANDOFF.md` S4.2 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`; remote `phase/s4-reports=A`, remote `main=P`, and no other path dirty at G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S4.3 plan anchors: `## 5. Information architecture and first-run flow` onboarding Value receipt; `## 6. Core workflow and state truth` Report truth and external-delivery non-claim; `## 9. Smallest reusable architecture` ready-PDF immutability and validated snapshot authority; `## 13. Quality budget and known bugs` broken-PDF/false-success blockers; `## 14. Learning plan, support, and diagnostics` share-sheet counter; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S4.3 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 may remain accepted S4.2 LF SHA-256 `4BF3B5D8947F11D5D248258FA9B7F63F577181CAFA325B851AECDC63C94CC2AA`; the first support mutation replaces it with the exact S4.3 object below, LF SHA-256 `58363B3FDAD13A57EF0F320F0DB92F80E020877A160D1131AC28BB61698DCDEF`.

## Outcome and acceptance

- Outcome: activate the existing single CheckRunner `ValueReceiptView` so `Report saved on this device.` offers `View report`, `Share PDF`, and `Done`; add one bounded delivery coordinator and one report-detail/preview surface that use only the exact cached ready PDF; add one exact-one-ready reopen action on Sign detail so a cold relaunch reopens the same Report ID/hash. Do not activate the Reports index.
- Receipt delivery: after finalization returns the receipt's exact newly finalized pending Report ID, perform exactly one existing S4.2 bounded `attemptPendingReport(id:)` call before enabling preview/share/export, and never call it a second time from receipt or navigation. Ready exposes delivery. Ordinary render failure stays failed/retryable with nil PDF fields and the receipt shows honest local non-delivery; the existing S4.2 Retry surface appears only after the next cold-launch reconciliation. Unsafe authority/storage failure likewise shows no delivery action and reaches the existing maintenance posture on the next cold-launch reconciliation. Never add an inline Retry or maintenance surface, regenerate, or mutate a ready Report.
- Ready authority: before every first load after navigation/relaunch, prove a unique schema-1 Report, exact Packet/source/snapshot identity, canonical snapshot bytes/hash/path, `pdfState=ready`, exact `pdfs/<lowercase-report-id>.pdf`, lowercase stored hash, absent expected stage, and matching regular nonsymlink cached bytes read under the frozen generation root. Ambiguity, path escape, symlink/special file, missing/mismatched bytes, invalid relationship/nullability, or dirty context fails closed without presenting/exporting.
- Detail/preview: display only facts frozen in the validated Report snapshot and preview the exact cached PDF bytes with PDFKit/system-native behavior. Never consult later mutable site/sign/issue labels for report truth, crop/tint/re-render evidence, or imply external delivery/review.
- Share: `Share PDF` opens the system share sheet with the exact cached PDF bytes/file. Attempt `report_share_sheet_presented` only after the sheet is actually presented; dismissal still counts, failed presentation does not. The best-effort diagnostic write never gates or rolls back presentation and never proves sent/opened/read/delivered.
- Files: expose a user-selected system Files destination and export byte-for-byte identical cached PDF content with a `.pdf` filename; cancel creates no app/domain mutation and no claimed export. No app-owned export history, destination bookmark, broad filesystem access, background copy, or overwrite inference exists.
- Done/reopen: `Done` returns to the same sign. Query all fully validated ready Reports whose unique Packet/source-to-asset chain belongs to that sign and expose direct reopen only when the count equals one. Count zero or greater than one omits the action or fails closed; never sort, select newest/current, persist a selection, derive replacement status, list, filter, show chronological history, or compare.
- GOLDEN: complete the existing fixture check, reach the sole receipt, obtain its ready Report, then receipt→preview→Share→Files uses byte-identical cached bytes/hash; `Done` returns to the sign, and a cold relaunch with exactly one sign-owned valid ready Report directly reopens that same Report ID, PDF bytes, and hash without regeneration or mutation.
- ALT-1: the user cancels/dismisses the system Share or Files presentation. A presented Share sheet may increment only the fixed best-effort share counter; no Report/Packet/source/snapshot/evidence/PDF state or bytes change, Files cancellation leaves no claimed destination output, and neither path records or displays sent/opened/read/delivered.
- UI acceptance: exercise normal imported-fixture onboarding through the existing sole receipt; prove enabled `View report`, exact `Share PDF`, and `Done`; preview legibility and report-truth copy; actual system Share presentation and dismissal; user Files presentation/cancel or deterministic test destination with byte/hash equality; Done-to-sign; relaunch/exact-one-ready reopen; one terminal in-app screenshot. Primary controls retain labels, button traits, logical order, non-color state, 44-point targets, Dynamic Type-safe scrolling, and deterministic VoiceOver focus.
- Negative family: pending/failed, duplicate/colliding authority, noncanonical/mismatched path/hash, dirty context, unknown schema/template, corrupt/noncanonical snapshot, broken Packet/source relationship, stage beside ready, missing/mismatched PDF, unsafe directory/symlink/special file, presentation failure, or destination cancellation never exposes false ready/delivery, mutates immutable authority, or touches an unowned path.
- Forbidden behavior: a second `ValueReceiptView`; new renderer/template/validator/storage contract; ready regeneration/demotion; Report/snapshot/evidence/Packet replacement or mutation; new schema/model/project/package/capability/permission; hosted URL/link, backend, upload, email provider, custom delivery protocol, contact picker, or delivery/sent/opened/read receipt; automatic sharing/export/background work; app-owned export ledger/bookmark; broad scan/link following/unowned access; rating, notification, paywall, purchase, or access gate; S4.4 Reports index/filter/history/current-revision/comparison; S4.5 correction; work/recheck/deletion/backup/restore/commerce/diagnostic-export/feedback; or any later-phase behavior.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s4-reports`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S4.3","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S4_3ReportDeliveryTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S4_3ValueReceiptUITests"]}` plus exactly one LF; 343 bytes.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S4.4 transition only. Main mutation before S4.5, force-push, merge, PR, ref rewrite/delete, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift`
- `FieldEvidenceApp/Features/Reports/ReportDetailView.swift`
- `FieldEvidenceApp/Features/Signs/SignDetailView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift`

Test paths:

- `FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift`
- `FieldEvidenceAppUITests/S4_3ValueReceiptUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`ReportDeliveryCoordinator` owns exact ready-authority loading, exactly one receipt-time pending attempt through retained S4.2/S4.1 behavior, immutable cached bytes, Share presentation accounting, Files bytes, and the sign-owned exact-one-ready lookup. New `ReportDetailView` owns detail/PDFKit/system presentation wrappers. The existing sole `ValueReceiptView` is activated; CheckRunner exposes only its already-held model/root/diagnostics boundary; Signs adds only direct exact-one-ready reopen. Synchronized source groups include the two new Swift files; UI reuses existing imported media, so no project/resource/fixture delta is needed. Existing seven-model schema, ReportRecoveryService/ReportRenderService/SnapshotValidatorV1/WorklightPDFRendererV1 bytes and contracts, DiagnosticsStore schema, AppShell Reports placeholder, and all later routes remain unchanged. `docs/execution/HANDOFF.md` is append-only post-green bookkeeping outside the implementation commit/cap. No other path may change.

## Execution

1. Fresh G0 observes A and proves `A^=M`; `M..A` is exactly the append-only S4.2 HANDOFF plus this S4.3 CURRENT_TASK transition; remote phase=A, remote main=P; accepted S4.2 evidence/pins/map/environment are complete; selector remains accepted S4.2; no other path is dirty.
2. Replace selector first, implement only the exact allowed paths, run structural/static Windows checks without claiming an iOS build, explicitly stage task-owned paths, and commit direct-child I.
3. Re-fetch, prove phase still at the intended parent, non-force push exact phase ref, and run the one-at-a-time persistent F25 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/artifact evidence; each terminal failure permits only the smallest diagnosed direct-child correction before a fresh candidate.
4. After accepted S4.3 evidence, re-fetch and append the complete S4.3 HANDOFF plus hydrate only immediate-next S4.4 CURRENT_TASK in one direct-child same-phase authority commit; keep main=P, push non-force, and require fresh S4.4 G0 before S4.4 implementation.

## Definition of done

- Exact green S4.3 evidence proves finalization triggers exactly one bounded pending-report attempt and never a second receipt/navigation attempt; the sole receipt activates View report/Share PDF/Done only for ready authority; preview, Share, Files, and exact-one-ready relaunch consume the same validated immutable cached PDF bytes/hash; zero or multiple sign-owned ready candidates never guess; system cancellation creates no false delivery fact or domain mutation; Share accounting follows actual presentation only; Done returns to sign; direct cold-relaunch reopen works without activating S4.4 index/history/comparison. Handoff records complete evidence, remote phase equals the accepted verification head, and only then may the exact S4.4 authority transition begin.

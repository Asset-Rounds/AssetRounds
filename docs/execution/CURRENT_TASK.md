# Current Task

## Program and card

- Phase / branch / card / global order: `S8 / phase/s8-quality / S8.3 / 34 of 36`.
- Card heading: `### S8.3 — Privacy-safe OSLog, MetricKit, and diagnostic export`.
- Position / boundary / immediate next card: `3 of 4 / phase boundary no / S8.4 only after accepted S8.3 evidence and fresh same-phase G0`.
- Program autopilot / phase autopilot / exact S8 span / boundary integration: `enabled through accepted S9.1 / enabled / S8.1,S8.2,S8.3,S8.4 / yes at S8.4 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S8 phase-main base: `P=0b1e506dd71ba704cbfb48787d6cfa1731024d83`; this exact accepted S7 phase-close/exact-main head remains byte-for-byte fixed throughout S8.
- Integrated/card base: `M=38e831412bc55389b76bf1ca17a4ee549ae6ef60`, the accepted S8.2 implementation and verification head.
- Accepted S8.2 evidence: run `31894016378` / job `95034408297`, exact `phase/s8-quality@M`, attempt 1, F25/UI enabled, terminal success, build plus `1/1` unit plus `1/1` UI green. Artifact `ios-ci-31894016378-1`, ID `9249494957`, size `11854010`, digest `sha256:daaed8fa813f49807de291741b4d0271c17082198da7e94940c365c4427aa518`; all `93/93` payload checksums matched; `SHA256SUMS.txt` SHA-256 `38E303F988262809E01BD3D412043E4D832283BED74CF7C2FC833D9B11F4E6F0`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.2 build `23C54`; Simulator UDID `9AA9ED9B-42D2-4F6E-B8B5-45AAB66D6404`; initial state `Shutdown`.
- S8.2 implementation lineage: authority `A=c1fb4578bda9f6dcff3faf5c618e1547882ae711`; initial implementation `I=8d372190641332f5daf4ccf9792f1b2d705b05c6`; successive task-scoped direct-child corrections remained inside the authorized proof/production envelope; accepted `E=M`. The 24 failed candidates recorded in HANDOFF were never rerun or accepted.
- Same-phase S8.3 transition authority must directly parent exact M and change only append-only `docs/execution/HANDOFF.md` plus this immediate-next `docs/execution/CURRENT_TASK.md`. Fresh G0 must observe and record that transition head as A without attempting to self-record its SHA here, prove `M..A` contains exactly those two paths, prove remote `phase/s8-quality=A`, and prove remote `main=P`.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S8.3 plan anchors: `## 14. Analytics, feedback, and learning` → no third-party analytics SDK, exact non-authoritative local counters, privacy-annotated unread/unattached OSLog, bounded MetricKit summary, exact owner-invoked `DiagnosticExportV1`, preview-before-attach, diagnostics excluded from backup and removed by Erase; `## 11. Build slices and release gates` → S8.3 privacy-safe OSLog/MetricKit plus exact owner-invoked diagnostic export. Global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S8.3 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7` / `workflow_dispatch`.
- Selector at G0 may still equal accepted S8.2 compact JSON plus LF, 355 bytes, SHA-256 `56ED06D4189ECDA0D643F680BC0291E78631F999207E896BAE6F8045FFD14807`; after complete G0 the first support mutation replaces it with the exact S8.3 object below, 348 bytes, SHA-256 `A3F9897C658B273AC991A30CFFF880458953682BF57516AEA552C4292F3A7626`.

## Outcome and acceptance

- Outcome: add privacy-safe fixed-message OSLog seams, one bounded MetricKit summary adapter, and one owner-invoked Settings preview/export flow for explicitly non-authoritative best-effort lower-bound diagnostics.
- Counter truth: reuse the exact existing `DiagnosticsV1` object and saturating lower-bound persistence behavior. Empty, reset, failed, or undercounted counters remain valid diagnostics and never gate access/payment, alter domain truth, or roll back successful work.
- OSLog truth: every app-authored diagnostic message uses explicit privacy-safe fixed descriptions/annotations and never interpolates customer/site/sign labels, addresses, notes, photo paths or hashes, StoreKit product/transaction/status values, report content, credentials, or raw diagnostic payload. OSLog is never read back, exported, or attached.
- MetricKit truth: retain only nullable `metricKit={crashCount,hangCount,launchTimeMilliseconds,peakMemoryBytes}`. Counts/bytes and every launch bucket are nonnegative; `launchTimeMilliseconds`, when present, has exactly `under500`, `from500Through999`, `from1000Through1999`, and `from2000Up`. Discard all raw payloads and every other MetricKit field.
- Export truth: canonical JSON has exactly six top-level keys: `app={build,version}`, `counters=<exact DiagnosticsV1 object>`, `device={model,osVersion}`, `diagnosticSchemaVersion=1`, `generatedAt`, and nullable `metricKit`. The file contains no image, report, database, backup, path/hash, label/note/address, StoreKit product/transaction/status, credential, raw log, or raw MetricKit diagnostic.
- Owner invocation truth: Settings opens a deterministic preview of the exact allowed context and explicitly labels counters as best-effort lower-bound/non-authoritative. Export to Files occurs only after the user invokes it; no automatic attachment, upload, background send, remote endpoint, or analytics transport exists.
- GOLDEN: controlled counter/system/MetricKit values produce byte-stable canonical allowed keys; hostile customer strings, paths, hashes, report content, and transaction identifiers are absent; an injected counter-write failure never gates payment/access or rolls back domain success.
- ALT-1: zero/undercounted counters plus absent MetricKit produce a valid minimal preview/export and make no exact-once, authoritative cohort, paid-state, or completeness claim.
- Unit truth: the one bounded unit class verifies exact canonical schema/order, nonnegative/overflow/failure behavior, hostile-string exclusion, MetricKit reduction, and nil-minimal export without inspecting or exporting OSLog.
- UI truth: one bounded Accessibility XXXL Settings flow opens the owner preview, proves exact non-authoritative/privacy copy and allowed summaries, exports through the system Files route without upload, and takes exactly one terminal in-app screenshot.
- Forbidden behavior: Sentry/PostHog/analytics SDK, remote logging/upload, raw OSLog readback, raw MetricKit payload persistence/export, raw database/media/report/backup export, customer/product/transaction/status content, access/payment decision, exact-once claim, cohort attribution, new schema/entity/dependency/permission/capability, S8.4 feedback/email behavior, support-address invention, signing, TestFlight, submission, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s8-quality`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.2`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S8.3","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S8_3DiagnosticExportUITests"]}` plus exactly one LF; 348 UTF-8 bytes, no BOM; SHA-256 `A3F9897C658B273AC991A30CFFF880458953682BF57516AEA552C4292F3A7626`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UITests result bundles; exactly one terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before the S8 boundary, settings/secrets, App Store Connect, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths (eight of the default ten-file cap):

- `FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift`
- `FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift`
- `FieldEvidenceApp/Infrastructure/Diagnostics/MetricKitDiagnosticsAdapter.swift`
- `FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift`
- `FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`

Test paths (two of the default five-file cap):

- `FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift`
- `FieldEvidenceAppUITests/S8_3DiagnosticExportUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other production, model, project, resource, fixture, asset, script, workflow, authority, or documentation path is allowed during S8.3 implementation. Existing canonical JSON, diagnostics counters, Settings/navigation, Files exporter patterns, design tokens, Erase/backup exclusions, models, routes, fixtures, and test helpers may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and verification

- Fresh G0 must prove transition A directly parents exact M, `M..A` changes only append-only HANDOFF plus immediate-next CURRENT_TASK, `P..A` preserves the accepted S8 lineage, remote `phase/s8-quality=A`, and remote `main=P`; it must reprove accepted S8.2 run/artifact/checksums and every pin above.
- Validate the exact S8.3 P12 selector object against runbook Section 6 and the workflow schema. The accepted S8.2 selector is permitted only as predecessor state; after complete G0 replace only `Scripts/ci-selection.json` with the frozen S8.3 object as the first implementation-support mutation.
- Implement only S8.3. Reuse the exact existing counters and Settings/data-right seams; do not add S8.4 feedback, mail, support-address, consent-attachment, or fallback behavior.
- Candidate recovery follows the persistent evidence-driven direct-child loop. Never weaken canonical/privacy exclusion, hostile-string proof, non-authoritative copy, counter-failure independence, real Files route, selector, screenshot count, or watchdogs.
- After accepted exact-head S8.3 CI, read `KNOWN_BUGS.md`, append immutable S8.3 HANDOFF, then enabled same-phase autopilot may commit/push exactly that append plus immediate-next S8.4 CURRENT_TASK and must run fresh S8.4 G0. Do not mutate `main` before the S8.4 phase boundary and do not start S9 work.

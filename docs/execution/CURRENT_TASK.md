# Current Task

## Program and card

- Phase / branch / card / global order: `S6 / phase/s6-data-rights / S6.1 / 21 of 36`.
- Card heading: `### S6.1 — Whole-sign lineage deletion and tombstones`.
- Position / boundary / immediate next card: `1 of 6 / phase boundary no / S6.2 only after accepted S6.1 evidence and fresh transition G0`.
- Program autopilot / phase autopilot / exact S6 span / boundary integration: `enabled through accepted S9.1 / enabled / S6.1,S6.2,S6.3,S6.4,S6.5,S6.6 / yes at S6.6 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S6 phase-main base and integrated/card base: `P=M=7c3c381055abde6f6b1020a9f3f599333ef47f40`; this is the accepted S5 HANDOFF-only phase-close and exact-main verification head. Remote `main=P` and remote `phase/s5-work-recheck=P` were reproved before creating the local S6 branch.
- Accepted S5.4 product evidence: `E=3fb262a1e584e8e3d67a1b0198ba5b4551cc98f4`; run `31767088432` / job `94665088396`, exact `phase/s5-work-recheck@E`, P12/UI enabled, `5/5` units and `1/1` UI green; artifact `ios-ci-31767088432-1`, ID `9206854883`, size `4599932`, GitHub/raw ZIP digest `sha256:ca548251dcf04f64fc0898dc64fddb94732849d8f4ae72ab7a2c65846367e7d5`; all `101/101` payloads matched; terminal screenshot SHA-256 `E91F5E1E05533E0F4EC71CE82EEC3688DC7FC3BB9EA5784D952EC042A724A802`.
- Accepted S5 phase-close evidence: HANDOFF-only `C=P`; phase run `31767711080` / job `94666890866`, exact `phase/s5-work-recheck@P`, success, artifact ID `9207216179`, size `4622205`, digest `sha256:60c0d44342fd002b9c951f752b80c369cb15fe192c06bd411091aad45525ae02`, all `101/101` payloads matched.
- Accepted exact-main integration evidence: run `31769275147` / job `94671606460`, exact `main@P`, attempt 1, P12/UI enabled, terminal success; artifact `ios-ci-31769275147-1`, ID `9207776274`, size `4525176`, digest `sha256:7c581b1101588075343fa509a20eae52c68f633b403fbe36fa6d29022d50e81b`; `SHA256SUMS.txt` SHA-256 `87AF4AFD27CEC9BC400A93B94C2AD9FAE682164AB291EF96A114AF66DE4DE7CD`; all `101/101` payloads independently matched; terminal screenshot SHA-256 `176E5DE74CB3C9188EC35E648B29C568BCAC7A5A08D7FC8FEEE8128B0ED6F467`.
- Exact-main recovery provenance: run `31768586849` / job `94669546631` at the same P passed build and units but failed only when hosted XCTest timed out evaluating an accessibility snapshot after the prerequisite Save action; no product assertion fired. It was not rerun by run ID. The one fresh-runner exact-head candidate above passed.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5 build `23F77`; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- Task-start authority A is the direct-child S6.1 hydration commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `P..A`: exactly one direct-child commit changing only this `docs/execution/CURRENT_TASK.md`; remote `phase/s6-data-rights=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S6.1 plan anchors: `## 6. Core workflow and state truth` → closed Site/Asset/WorkflowRecord/EvidenceFile/Issue/Packet/Report relationships and live-sign truth; `## 7. Free evaluation, subscriptions, and payments` → free-evaluation roots survive ordinary deletion as anonymous counted tombstones and only the concurrent live-sign slot is freed; `## 9. Smallest reusable architecture` → one bounded deletion intent/rule/service/view over the existing immutable-generation store; `## 10. Storage, crash consistency, and one-off bug prevention` → canonical `DeletionIntentV1`, one SwiftData save, exact-path cleanup, and closed recovery; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S6.1 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S5.4 compact JSON plus LF, 335 bytes, SHA-256 `26B050C4BDE1BFDF9CC5324A6FE63DFE16AD36AEF215052FDA9480E3FB142A64`; after G0 the first support mutation replaces it with the exact S6.1 object below, 336 bytes, SHA-256 `A66022B9E5B51BF032C2570518025121B3F0D7FCDB7362319AA85083774CEFC7`.

## Outcome and acceptance

- Outcome: from one uniquely validated live Asset, require the exact destructive confirmation, journal the complete referentially closed visible graph and exact owned paths, perform one SwiftData save that removes the Asset lineage and materializes counted-root tombstones, then delete only the frozen intent-owned files; free the live-sign slot without resetting the free-report count.
- Confirmation copy is exactly `Delete this sign, its photos, and its reports from this app? This cannot be undone. Your free-report count will not reset. Erase All removes the remaining anonymous count.` with **Cancel** and destructive **Delete sign**. Cancel creates no journal, row mutation, tombstone, or file change.
- `DeletionIntentV1` lives at `Application Support/FieldEvidenceOperations/deletion/<deletion-id>.json`; canonical JSON has exactly `assetID`, `countedPacketTombstones`, `deletionID`, `generationID`, `phase`, `relativePaths`, and `schemaVersion`; schema is 1; phase is only `prepared|database_committed`; relative paths are unique sorted normalized generation-relative strings; tombstones are exact post-delete Packet DTOs.
- Closed graph truth: prove one schema-1 live Asset and its Site; every WorkflowRecord for the Asset including revisions/corrections; every linked EvidenceFile and canonical original/thumbnail; every linked Issue; every Packet and Report including replacement history; every report snapshot and ready PDF path; all global reverse edges, identities, mutation/revision/report chains, files, hashes, and row cardinalities. Reject an ambiguous, forked, cross-Asset, dangling, duplicate, colliding, malformed, dirty, or unsafe graph rather than sorting or guessing.
- Database truth: one SwiftData save removes all visible Asset-owned WorkflowRecord/EvidenceFile/Issue/Report rows, removes every uncounted Packet, replaces each counted Packet with one content-free tombstone retaining only its schema/anonymous IDs/evaluation flag/created and deletion instants with `currentRecordID=nil`, removes the Asset, and removes the Site only when no other Asset uses it. No visible row, content path, or dangling ID remains; unrelated Assets/Sites/roots remain byte-for-byte unchanged.
- File truth: only after the database commit, remove exactly the intent's anchored, no-follow, normalized generation-relative paths. Never follow a symlink, traverse an unsafe ancestor, delete an unlisted path, infer by directory age, or touch retained/unowned bytes. Exact owned staging/temporary/journal cleanup is mandatory; a failure remains recoverable and never rolls back committed tombstone truth.
- GOLDEN: one complete Asset lineage containing counted and uncounted Packets is deleted after the exact confirmation; every visible row/file in the closed lineage disappears; its Site disappears only when empty; one valid anonymous tombstone remains per counted root; uncounted roots disappear; the app returns to Welcome and permits a new live sign without resetting evaluation consumption.
- ALT-1: interruption while `prepared` and the live Asset remains cancels the exact intent without changing domain/files; interruption after the database commit recognizes only the exact committed tombstone set, advances/accepts `database_committed`, and completes only intent-owned path cleanup on relaunch. Phase/presence mismatch, unknown phase, malformed intent, partial row state, or mismatched tombstone enters the existing closed maintenance route and deletes nothing.
- Recovery ordering: activate StartupRouter's existing `.deletion` checkpoint after finalization recovery and before media/PDF recovery; reconcile every canonical deletion intent under the current frozen generation identity before feature writes. Recovery is idempotent, exact-path, and never guesses a newest intent or foreign generation.
- UI/accessibility: expose deletion only from the current live sign detail; the confirmation scrolls at every Dynamic Type category, destructive and cancel controls are logically ordered and at least 44×44 points, initial and completion focus are deterministic, double tap cannot create a second intent, errors retain the sign and offer a bounded retry, and successful deletion resets navigation/state to Welcome. The sole UI test builds one persisted report-bearing Issue/work/recheck lineage, relaunches at Accessibility XXXL, verifies Cancel preserves it, confirms **Delete sign**, proves Welcome/no sign/report/issue content, creates a replacement live sign, and retains one terminal in-app screenshot.
- Negative family: dirty context; missing/wrong/nonlive Asset or generation; duplicate/colliding Site/Asset/record/evidence/Issue/Packet/root/Report/intent identities; revision/replacement/finalization fork or cycle; cross-Asset or dangling edge; incomplete Report/snapshot/PDF authority; invalid evidence path/hash/bytes/JPEG; counted-root/tombstone mismatch; unsafe path, symlink, hardlink/special file, or ancestor replacement; journal write/replace/remove, model-save, rollback, exact-file cleanup, and relaunch interruption before/after commit. Every case fails closed or remains exactly recoverable with unrelated rows/files untouched and no fragment deletion, partial tombstone, staging/final/journal orphan, or evaluation refund.
- Forbidden behavior: Packet/report/Issue fragment delete; undo/trash/retention window; cloud/backend/account deletion; deleting or resetting counted roots during ordinary sign deletion; entitlement/StoreKit change; Erase All implementation; backup/export/import/restore; schema/model/project/package/capability/permission change; correction/work/recheck behavior change; diagnostics/feedback/release; S6.2+ implementation.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s6-data-rights`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S6.1","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S6_1DeletionGraphTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S6_1DeletionUITests"]}` plus exactly one LF; 336 UTF-8 bytes, no BOM; SHA-256 `A66022B9E5B51BF032C2570518025121B3F0D7FCDB7362319AA85083774CEFC7`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before accepted S6.6 boundary integration, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift`
- `FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift`
- `FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`
- `FieldEvidenceApp/Features/Signs/SignDetailView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`

Test paths:

- `FieldEvidenceAppTests/S6_1DeletionGraphTests.swift`
- `FieldEvidenceAppUITests/S6_1DeletionUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, project, model, resource, fixture, script, workflow, authority, or documentation path is allowed during S6.1 implementation. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s6-data-rights`, `A^=P`, exact CURRENT_TASK-only `P..A`, remote phase=A, remote main=P, all pins and accepted S5.4 product/phase/exact-main evidence live and exact, the accepted S5.4 selector still byte-exact, and the six-production/two-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S6.1 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S6.1 CI, read `KNOWN_BUGS.md`, append the immutable card HANDOFF, and—only if fresh refs still match—commit/push exactly that append plus immediate-next S6.2 `CURRENT_TASK.md`; then run fresh S6.2 G0. Do not mutate `main`.

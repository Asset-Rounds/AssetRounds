# Current Task

## Program and card

- Phase / branch / card / global order: `S6 / phase/s6-data-rights / S6.5 / 25 of 36`.
- Card heading: `### S6.5 — Replace existing data and monotonic union`.
- Position / boundary / immediate next card: `5 of 6 / phase boundary no / S6.6 only after accepted S6.5 evidence and fresh transition G0`.
- Program autopilot / phase autopilot / exact S6 span / boundary integration: `enabled through accepted S9.1 / enabled / S6.1,S6.2,S6.3,S6.4,S6.5,S6.6 / yes at S6.6 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S6 phase-main base: `P=7c3c381055abde6f6b1020a9f3f599333ef47f40`; this is the accepted S5 HANDOFF-only phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S6.
- Integrated/card base: `M=d1e2aae38f96c37e5b395bc3fa1ccc9fac3f3d40`; this is accepted S6.4 product and verification evidence on `phase/s6-data-rights`.
- Accepted S6.4 workflow evidence: run `31801293840` / job `94769659418`, exact `phase/s6-data-rights@M`, attempt 1, F25/UI enabled, terminal success, `13/13` units and `1/1` UI green; URL `https://github.com/palatis3/AssetRounds/actions/runs/31801293840`.
- Accepted S6.4 artifact: `ios-ci-31801293840-1`, ID `9219827280`, size `6144786`, GitHub digest `sha256:26b4836c500ab8115b0f30e9f031fd102fb5971eb682063ff7c303332db561d7`; `SHA256SUMS.txt` SHA-256 `D2391270A08091144646BC064D36914FD229506274EA8083FABC148FA2437670`; all `117/117` listed payloads independently matched; terminal screenshot SHA-256 `A7CB0CA68EA27EC6ABADB4CA6D1A6BA3D1217B021FB23D282D94F1B3DCEEB035`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- S6.4 recovery provenance remains immutable: failed candidates `31800195901` and `31800623158` were diagnosed and never accepted or rerun by run ID; successive direct-child corrections culminated in accepted M.
- Mandatory later integration evidence remains frozen: the accepted S6.3 UI proof used a cold boundary because a prior-card `CheckRunnerCoordinator.finalizationAttempt` can survive a completed recheck and misclassify a same-session fresh check. That earlier reusable seam is outside S6.5 and must be exercised and corrected by S8.1 before release.
- Task-start authority A is the direct-child S6.5 transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child commit changing only an append to `docs/execution/HANDOFF.md` plus this replacement `docs/execution/CURRENT_TASK.md`; remote `phase/s6-data-rights=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S6.5 plan anchors: `## 7. Free evaluation, subscriptions, and payments` → installation-scoped monotonic evaluation accounting; `## 10. Storage, crash consistency, and one-off bug prevention` → existing-data restore, counted-root union, current-only tombstones, immutable generation switch, and the closed recovery matrix; `### V4Backup@1` → validated schema-1 package and no entitlement/diagnostic import; `## 11. Build slices and release gates` → S6.5 replacement restore/union; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S6.5 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S6.4 compact JSON plus LF, 343 bytes, SHA-256 `C69F59FF6AD09508D0253CD96D72B950F62B435E62C2BDB69AEBCC4DD4FD1552`; after G0 the first support mutation replaces it with the exact S6.5 object below, 344 bytes, SHA-256 `92DADA795227BD92E1B0A39D7FB47279C35BB95E056ECC430ADE1C4EECA725FE`.

## Outcome and acceptance

- Outcome: activate Settings **Restore data backup** for a proven valid nonempty current generation; use the same importer, validator, progress surface, immutable-generation service, exact seven-key journal, pointer switch, session activation, recovery path, and external package boundary as S6.4 while adding current/incoming summary, optional **Back up current data**, explicit **Replace current data**, and a monotonic counted-root union.
- Entry-mode truth: Welcome and eligible maintenance remain the S6.4 empty-install route and never replace nonempty authority. Settings alone selects replacement mode. Both modes call the same restore sheet/service with an explicit frozen mode; a retained/default callback may not silently turn Welcome into replacement or Settings into empty-only restore. **Restore data backup** remains distinct from **Restore Purchases**.
- Summary/confirmation truth: after closed package validation and before any generation/journal/pointer mutation, show deterministic current and incoming sign/report/photo counts, exported date, and declared size; offer the existing **Back up current data** route; require the exact destructive action **Replace current data**. The backup action remains user-selected Files export and is never automatic or claimed as complete without a destination.
- Cancel truth: Cancel before confirmation discards only the exact operation-owned imported package stage, leaves no Restore generation stage or journal, and changes no current row, media, snapshot, PDF, Packet, root count, pointer, generation, diagnostic, entitlement, external package, or UI session.
- Union rule: derive the unique set of every current and incoming `evaluationCounted=true` stable root, live or tombstoned. Incoming roots keep their exact incoming live/tombstone authority. Each current-only counted root becomes one valid staged Packet tombstone copying its current Packet ID, stable root, evaluation flag, and creation instant, with nil current record and the frozen replacement instant as deletion time. Restored live roots are never duplicated or tombstoned.
- Collision truth: reject before mutation if a Packet ID or stable-root overlap has different frozen facts, if one root maps to multiple Packets, if current authority is dirty/ambiguous/malformed, or if the materialized staged graph does not contain exactly the incoming records plus required current-only tombstones. Counted roots after replacement must equal the exact current/incoming union and can never decrease.
- Storage/materialization truth: preserve S6.4 capacity, descriptor, no-follow, exact-tree, DTO/file/hash, schema/pack/template, report, media, snapshot, pending/failed, pointer, retired-set, staging-exclusivity, active-Erase, and no-extra-byte gates. Materialize only a fresh immutable generation; never rename, overwrite, or delete the active generation.
- Journal/recovery truth: use the unchanged canonical seven-key `RestoreIntentV1` and four phases `prepared|generation_installed|pointer_switched|new_generation_validated`. Recovery continues to accept only the closed old/new/stage/pointer/retired presence matrix and ends at the prior valid generation or fully validated replacement generation; malformed, extra, colliding, or ambiguous authority opens maintenance and deletes nothing.
- Session/report truth: switch canonical `current.json` only after full union validation; activate the new coordinator/root once; retire old only after reopened validation; rerender pending Reports idempotently once; retain failed Reports for explicit Retry; preserve ready Report bytes/hashes; and import no entitlement, commerce, diagnostics, journal, staging, temp, secret, or external-package mutation.
- GOLDEN: current counted root A plus a validated different backup with live counted root B yields only the incoming live customer graph, one valid current-only tombstone for A, exact counted roots `{A,B}`, no duplicate B, no evaluation decrement, no entitlement/diagnostic import, canonical pointer to the validated replacement generation, retired old generation, no Restore stage/journal, cold-reopen truth, and one Accessibility XXXL terminal screenshot.
- ALT-1: after validating a different backup and showing exact current/incoming summary, Cancel before confirmation removes the selected operation stage and leaves every live byte, pointer, generation, root, counter, external package, entitlement, and diagnostic unchanged. The same bounded test family rejects collisions and proves replacement only begins after explicit confirmation.
- Accessibility/UI: reuse Worklight semantic components and the S6.4 progress/error surface; keep logical focus/order, non-color status, at least 44×44 controls, and every Dynamic Type category; lock duplicate activation; keep **Back up current data**, Cancel, and **Replace current data** distinct and reachable at Accessibility XXXL.
- Forbidden behavior: live-content merge; evaluation decrement; restored-root duplication; entitlement/diagnostic import; automatic backup; replacement from Welcome/maintenance; active-generation rename/delete; newest-directory guess; noncanonical pointer/journal; partial import; automatic repair/migration; failed-report automatic retry; Restore Purchases conflation; backend/cloud/account/sync; schema/model/project/capability/permission change; S6.6 Erase behavior; signing, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s6-data-rights`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `F25 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S6.5","tier":"F25","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":900,"testTimeoutSeconds":1200,"uiTimeoutSeconds":1800,"totalBudgetSeconds":4500,"unitTestSelectors":["FieldEvidenceAppTests/S6_5ReplacementUnionTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S6_5ReplacementUITests"]}` plus exactly one LF; 344 UTF-8 bytes, no BOM; SHA-256 `92DADA795227BD92E1B0A39D7FB47279C35BB95E056ECC430ADE1C4EECA725FE`.
- Exact commands: `bash Scripts/run-with-timeout.sh 900 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 1200 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 1800 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before accepted S6.6 boundary integration, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift`
- `FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/App/FieldEvidenceAppApp.swift`

Test paths:

- `FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift`
- `FieldEvidenceAppUITests/S6_5ReplacementUITests.swift`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, script, workflow, authority, or documentation path is allowed during S6.5 implementation. Existing S6.3 importer/validator/fixtures, S6.4 Restore intent/store/generation/session/recovery authority, `BackupExportView`, canonical JSON, report/media/snapshot validators, sign-pack registry, storage preflight, diagnostics, and design tokens may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s6-data-rights`, `A^=M`, exact one-commit HANDOFF-append-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins, accepted S6.4 exact-head run/artifact, accepted S6.4 selector byte-exact, and the six-production/two-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S6.5 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S6.5 CI, read `KNOWN_BUGS.md`, append the immutable card HANDOFF, and—only if fresh refs still match—commit/push exactly that append plus immediate-next S6.6 `CURRENT_TASK.md`; then run fresh S6.6 G0. Do not mutate `main` before accepted S6.6 boundary integration.

# Current Task

## Program and card

- Phase / branch / card / global order: `S6 / phase/s6-data-rights / S6.2 / 22 of 36`.
- Card heading: `### S6.2 — Proprietary UTI and deterministic backup export`.
- Position / boundary / immediate next card: `2 of 6 / phase boundary no / S6.3 only after accepted S6.2 evidence and fresh transition G0`.
- Program autopilot / phase autopilot / exact S6 span / boundary integration: `enabled through accepted S9.1 / enabled / S6.1,S6.2,S6.3,S6.4,S6.5,S6.6 / yes at S6.6 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S6 phase-main base: `P=7c3c381055abde6f6b1020a9f3f599333ef47f40`; this is the accepted S5 HANDOFF-only phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S6.
- Integrated/card base: `M=97a29dd8da93718d5e0e29e8e67ff4d6f43c6915`; this is accepted S6.1 product and verification evidence on `phase/s6-data-rights`.
- Accepted S6.1 workflow evidence: run `31777874383` / job `94697039768`, exact `phase/s6-data-rights@M`, attempt 1, P12/UI enabled, terminal success, `5/5` units and `1/1` UI green; URL `https://github.com/palatis3/AssetRounds/actions/runs/31777874383`.
- Accepted S6.1 artifact: `ios-ci-31777874383-1`, ID `9210878757`, size `4877915`, GitHub digest `sha256:78dd8e60646acb161005ab76c16e0d5907aa51ccbd4b833dc561611f30d4ae76`; `SHA256SUMS.txt` SHA-256 `1AC56FC2DB09CB833E32EFFD4B1FE9AC79DE0A1B29D73F8DA92C36877EDE4B2D`; all `101/101` nonmanifest payloads independently matched; terminal screenshot SHA-256 `F3F95756E8B4A49B17CB8436248BDDD07ED0ADF63FC89178D6C43598A8E8312D`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5 build `23F77`; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- S6.1 recovery provenance remains immutable: failed candidates `31771862379`, `31772366306`, `31773712802`, `31774536547`, `31775370122`, `31776379989`, and `31777331626` were diagnosed and never accepted or rerun by run ID; the fresh exact-head candidate above is the sole accepted S6.1 result.
- Task-start authority A is the direct-child S6.2 transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child commit changing only an append to `docs/execution/HANDOFF.md` plus this replacement `docs/execution/CURRENT_TASK.md`; remote `phase/s6-data-rights=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S6.2 plan anchors: `## 10. Storage, crash consistency, and one-off bug prevention` → reusable actual-target-volume storage preflight and immutable-generation file authority; `### V4Backup@1` → exact FileWrapper package, UTI, members, canonical manifest/records, unchanged media mappings, counted-root equality, exclusions, ready/pending/failed truth, exact warning, and confirmed destination; global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S6.2 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S6.1 compact JSON plus LF, 336 bytes, SHA-256 `A66022B9E5B51BF032C2570518025121B3F0D7FCDB7362319AA85083774CEFC7`; after G0 the first support mutation replaces it with the exact S6.2 object below, 339 bytes, SHA-256 `E582CB7BB4F435ED582163A9F2E763742D7F01A94F8B0ED3EA926731579DF1FE`.

## Outcome and acceptance

- Outcome: export the uniquely validated current immutable generation as one deterministic `V4Backup@1` user-selected FileWrapper directory package, after actual-destination capacity preflight and destination confirmation, without changing live data.
- Package identity: exported UTI `com.palatis3.fieldrecordbackup`, conforming to `com.apple.package`, extension `.fieldrecordbackup`; directory package only, never ZIP. The project delta adds only that exported package UTI/extension and no schema, package, capability, entitlement, or permission.
- Exact members: `manifest.json`, `records.json`, `media/<evidence-uuid>.jpg`, `thumbnails/<evidence-uuid>.jpg`, `snapshots/<report-uuid>.json`, and ready-only `pdfs/<report-uuid>.pdf`. Every member path is NFC, slash-separated, normalized, relative, unique, nonsymlink, and contains no absolute, empty, `.`, or `..` segment.
- Media truth: copy exact validated live `evidence/<evidence-uuid>/original.jpg` bytes unchanged to `media/<evidence-uuid>.jpg` and exact validated live thumbnail bytes unchanged to `thumbnails/<evidence-uuid>.jpg`; never re-encode, substitute, crop, omit, or infer. Include every immutable report snapshot. Include a PDF only for a `ready` Report whose path/hash/bytes validate; pending and failed Reports retain snapshots but no PDF member.
- Canonical `manifest.json` has exactly `backupSchemaVersion`, `consumedEvaluationRootIDs`, `declaredPayloadByteCount`, `entries`, `exportedAt`, `packs`, and `source`; version is integer 1. Consumed roots are unique lowercase UUIDs sorted ascending and exactly equal the `evaluationCounted=true` Packet set in `records.json`. Payload count excludes `manifest.json`. Entries cover every other member exactly once as `{byteCount,mimeType,path,sha256}` sorted by path. Packs are `{contentVersion,packID,schemaVersion}` sorted by pack ID/version. Source is `{appBuild,appVersion,persistentSchemaVersion:1,recordsSchemaVersion:1}`.
- Canonical `records.json` has exactly `assets`, `evidenceFiles`, `issues`, `packets`, `recordsSchemaVersion`, `reports`, `sites`, and `workflowRecords`; version is integer 1. Arrays sort by ID and each stable DTO contains every exact field and nullability of the frozen seven-model contract. UUIDs, dates, hashes, relationships, and tombstone `currentRecordID:null` use the frozen canonical forms; no SwiftData internals or omitted model key is accepted.
- Export includes current records, counted tombstones, original media, thumbnails, immutable snapshots, pack/version references, and ready PDFs. It excludes StoreKit/commerce cache, diagnostics, operation/restore/erase/deletion/finalization journals, staging, temporary files, OS metadata, Keychain/secrets, and unrelated caches. It makes no app-level encryption claim and can never grant paid access.
- Storage truth: preflight important-usage capacity on the actual user-selected target volume before destination-package creation; require declared payload plus 20 percent plus the shared 64 MiB reserve. A failed preflight creates no destination package, mutates no live row/file, and preserves the selected package path for a bounded retry only when the platform contract permits.
- User truth: before export show exact sign/report/photo counts and exactly `This backup contains sign details, notes, photos, and reports. It does not contain your subscription. Store and share it securely.` Export proceeds only after the user confirms the system Files destination. `Back up current data` is the only authority-backed custom action copy available from the pinned plan and may be reused for this backup action; all other new custom result/error copy remains unresolved and must not be selected or implemented. System-provided Files exporter copy is platform copy, not invented product copy.
- GOLDEN: export the checked-in mixed minimal-live, Issue/recheck, correction, tombstone, ready, pending, and failed fixture; independently recompute exact package paths, sign/report/photo counts, byte counts, SHA-256 values, unchanged original/thumbnail bytes, counted-root and live-slot equality, exact warning, one ready PDF only, and every pending/failed snapshot present. Confirm a user-selected Files destination and retain one terminal in-app Accessibility XXXL screenshot.
- ALT-1: inject actual-destination capacity below declared payload plus 20 percent plus the shared reserve; block before any destination package exists and prove every live row/file remains byte-for-byte unchanged.
- Recovery/compatibility truth: export is a read-only snapshot operation over the exact current generation; fail closed on dirty context, root identity change, malformed/colliding rows, broken relationships, invalid media/snapshot/PDF authority, path/symlink/special-file violations, duplicate member/path, hash/count mismatch, unknown pack/schema/template, or capacity failure. Pending regeneration and failed Retry semantics remain unchanged.
- Accessibility/UI: expose one Settings backup entry through the existing shell/navigation, show deterministic counts/warning and a single enabled action, use logical focus and at least 44×44 controls at every Dynamic Type category, prevent double-tap duplicate preparation/export, and keep destination cancellation read-only. The UI proof relaunches at Accessibility XXXL, verifies the exact warning/counts, confirms a Files destination through the bounded test seam, proves one package, and retains one terminal in-app screenshot.
- Forbidden behavior: ZIP/archive dependency; encryption claim; import, staging, package ingestion, restore, replacement/union, Erase All, commerce/entitlement/diagnostics export, schema/model migration, backend/cloud/account/sync, package/capability/permission addition, generated media/PDF substitution, mutation of live data, broad filesystem scan, S6.3+ implementation, signing, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s6-data-rights`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S6.2","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S6_2BackupExportTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S6_2BackupExportUITests"]}` plus exactly one LF; 339 UTF-8 bytes, no BOM; SHA-256 `E582CB7BB4F435ED582163A9F2E763742D7F01A94F8B0ED3EA926731579DF1FE`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before accepted S6.6 boundary integration, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift`
- `FieldEvidenceApp/Features/Settings/BackupExportView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`
- `FieldEvidenceApp/Features/Signs/SignsRootView.swift`
- `FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift`
- `FieldEvidenceApp.xcodeproj/project.pbxproj`

Test paths:

- `FieldEvidenceAppTests/S6_2BackupExportTests.swift`
- `FieldEvidenceAppUITests/S6_2BackupExportUITests.swift`
- `FieldEvidenceAppTests/Fixtures/S6_2V4BackupRecordsV1.json`
- `FieldEvidenceAppTests/Fixtures/S6_2V4BackupManifestV1.json`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, resource, fixture, script, workflow, authority, or documentation path is allowed during S6.2 implementation. Existing report/media validators, DTO models, canonical snapshot encoder, generation authority, design tokens, and fixtures may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s6-data-rights`, `A^=M`, exact one-commit HANDOFF-append-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins, accepted S6.1 exact-head run/artifact, accepted S6.1 selector byte-exact, and the eight-production/four-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S6.2 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S6.2 CI, read `KNOWN_BUGS.md`, append the immutable card HANDOFF, and—only if fresh refs still match—commit/push exactly that append plus immediate-next S6.3 `CURRENT_TASK.md`; then run fresh S6.3 G0. Do not mutate `main`.

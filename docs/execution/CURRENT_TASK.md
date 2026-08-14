# Current Task

## Program and card

- Phase / branch / card / global order: `S6 / phase/s6-data-rights / S6.3 / 23 of 36`.
- Card heading: `### S6.3 — Backup import, staging, and closed validation`.
- Position / boundary / immediate next card: `3 of 6 / phase boundary no / S6.4 only after accepted S6.3 evidence and fresh transition G0`.
- Program autopilot / phase autopilot / exact S6 span / boundary integration: `enabled through accepted S9.1 / enabled / S6.1,S6.2,S6.3,S6.4,S6.5,S6.6 / yes at S6.6 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S6 phase-main base: `P=7c3c381055abde6f6b1020a9f3f599333ef47f40`; this is the accepted S5 HANDOFF-only phase-close and exact-main verification head. It remains byte-for-byte fixed throughout S6.
- Integrated/card base: `M=de0faeda88e2d3021f6944260b86fa128ea8611f`; this is accepted S6.2 product and verification evidence on `phase/s6-data-rights`.
- Accepted S6.2 workflow evidence: run `31783299741` / job `94713542856`, exact `phase/s6-data-rights@M`, attempt 1, P12/UI enabled, terminal success, `4/4` units and `1/1` UI green; URL `https://github.com/palatis3/AssetRounds/actions/runs/31783299741`.
- Accepted S6.2 artifact: `ios-ci-31783299741-1`, ID `9212708214`, size `3428030`, GitHub digest `sha256:90590c30d5c6f3f18fa9b41d47069bfed681eb7b5d9234c9d80086e7586fb548`; `SHA256SUMS.txt` SHA-256 `C5FC8CB810984D916CBC909BD9C3A782355AFA901E1321F3D0D56665941B2723`; all `99/99` nonmanifest payloads independently matched; terminal screenshot SHA-256 `87B0258A58B66588088E37485FE868C7565408B7934182B6FD5F30019877576B`.
- Accepted environment: `macos26` image `20260728.0273.1`; Xcode 26.6 build `17F113`; iPhone 17 / iOS 26.5; Simulator UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`.
- S6.2 recovery provenance remains immutable: failed candidates `31781228277`, `31781716916`, and `31782408147` were diagnosed and never accepted or rerun by run ID; the direct-child authority correction `c10d77fec200edccb42821e14b27811b93788deb` and accepted exact-head candidate above are the sole accepted continuation.
- Task-start authority A is the direct-child S6.3 transition commit observed after it exists at fresh G0; this file deliberately never self-records that future SHA.
- Required `M..A`: exactly one direct-child commit changing only an append to `docs/execution/HANDOFF.md` plus this replacement `docs/execution/CURRENT_TASK.md`; remote `phase/s6-data-rights=A`, remote `main=P`, and no other dirty path at fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S6.3 plan anchors: `## 10. Storage, crash consistency, and one-off bug prevention` → restore storage estimate and immutable-generation staging; `### V4Backup@1` → exact package members, canonical manifest/records, security-scoped copy, closed rejection rules, counted-root equality, and pending/failed semantics; `## 11. Build slices and release gates` → S6.3 security-scoped import/stage/hash/path/schema/relationship validation; global execution anchors remain `## 16` and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79` / selected card S6.3 only.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector at G0 remains accepted S6.2 compact JSON plus LF, 339 bytes, SHA-256 `E582CB7BB4F435ED582163A9F2E763742D7F01A94F8B0ED3EA926731579DF1FE`; after G0 the first support mutation replaces it with the exact S6.3 object below, 347 bytes, SHA-256 `BFB97B3FF1BC13B36ED001D9CB26B2762D49C81F54A586464114272621DB5F18`.

## Outcome and acceptance

- Outcome: obtain security-scoped access to one selected `.fieldrecordbackup` directory package only long enough to coordinate-copy it into app-owned restore staging, release that access, perform complete closed validation, and expose a deterministic customer-content-safe validation summary without mutating the live generation.
- S6.3 does not activate an ordinary customer restore route. `Restore data backup` begins only in S6.4; Settings replacement restore, `Back up current data`, and `Replace current data` begin only in S6.5. The shell may expose the summary solely through the existing bounded UI-test launch seam. No new custom public action, result, or error copy may be selected in this card.
- Package boundary: accept only exported UTI `com.palatis3.fieldrecordbackup`, conforming to `com.apple.package`, extension `.fieldrecordbackup`, as a directory package. The selected external package is read only during coordinated copy; subsequent validation reads only the staged copy. Never modify, repair, normalize, or partially import the selected package.
- Storage truth: before staging, perform overflow-safe important-usage capacity preflight on the actual app staging volume for twice `declaredPayloadByteCount` plus 20 percent plus the shared 64 MiB reserve. Failure creates no stage, changes no live row/file, and presents no success summary.
- Exact-member truth: require exactly one canonical `manifest.json`, one canonical `records.json`, every declared `media/<evidence-uuid>.jpg`, `thumbnails/<evidence-uuid>.jpg`, `snapshots/<report-uuid>.json`, and ready-only `pdfs/<report-uuid>.pdf`, with no missing, extra, duplicate, aliased, hard-linked, symlinked, special, hidden metadata, or nested undeclared member.
- Path truth: every manifest and discovered member path is byte-agreeing NFC, slash-separated, normalized, relative, unique, and free of absolute roots, backslashes, empty segments, `.`, `..`, control characters, case-fold collisions, percent-decoded aliases, and traversal through a link or replaced ancestor. Reads are anchored/no-follow within the staged package.
- Canonical truth: decode `manifest.json` and `records.json` only through exact schema-1 closed contracts, reject unknown/missing keys and noncanonical UUID/date/hash/number/null forms, then require byte-for-byte equality with the canonical re-encoding. `declaredPayloadByteCount`, every entry byte count/hash/MIME/path, sorted unique packs, and source schema versions must match exact staged bytes.
- Media truth: every original and thumbnail is a canonical single-frame JPEG that independently passes `MediaNormalizerV1` validation, matches its EvidenceFile MIME/count/hash fields, and preserves the exact backup bytes. No re-encoding, substitution, metadata repair, extension trust, or thumbnail regeneration is allowed.
- Report truth: every report snapshot is canonical, matches its Report path/hash/source/packet identity, and validates against the frozen pack/template and complete stored graph. A ready Report requires its exact declared PDF path/hash/bytes; pending and failed Reports require no PDF member. Validation never renders, retries, changes state, or infers a missing delivery.
- Graph truth: require unique noncolliding IDs and a referentially closed seven-model graph: Site/Asset ownership; exact Asset pack; completed/draft WorkflowRecord stage, revision, parent, Issue, Packet, and evidence-source invariants; EvidenceFile ownership and purpose; Issue open/resolution lineage; Packet stable-root/current-record/tombstone truth; Report source/replacement chains; and exact one-to-one file ownership. Reject cycles, forks, stray rows/files, cross-Asset relationships, ambiguous current records/reports, unknown pack/schema/template, or any value not representable by the frozen model contract.
- Evaluation truth: manifest `consumedEvaluationRootIDs` is unique sorted lowercase UUIDs and equals exactly every `evaluationCounted=true` Packet stable root in records. Tombstones retain only their frozen Packet fields with `currentRecordID:null`; live roots and report revisions never duplicate or reduce consumption.
- Summary truth: one successful validation returns deterministic incoming sign/report/photo counts, export date, declared size, sorted pack references, consumed-root count, and live/tombstoned slot counts derived only from the validated staged package. Reuse existing S6.2 count formatting and existing system/semantic components; do not expose customer labels, addresses, notes, hashes, paths, photo bytes, report content, commerce, diagnostics, or secrets in the summary.
- Staging lifetime: invalid selection, copy failure, capacity failure, validation failure, cancellation, replacement selection, and view dismissal remove only the exact operation-owned staged package. A successful validated stage may live only as the immutable handoff value needed by S6.4; it is not installed, opened as current SwiftData, or merged in S6.3.
- GOLDEN: materialize the checked-in exact mixed fixture as a directory package, coordinate-copy it through the same importer, and independently recompute deterministic counts/date/size/pack/root/slot summary, exact member set, canonical JSON bytes, hashes, MIME, unchanged original/thumbnail bytes, schema/pack/template truth, complete relationships, counted-root equality, ready PDF presence, and pending/failed PDF absence. Render the safe summary at Accessibility XXXL through the bounded test seam and retain one terminal in-app screenshot.
- ALT-1: one bounded parameterized invalid-package family covers missing/extra/duplicate/unsafe members, symlink/special/hard-link/ancestor substitution, noncanonical JSON, unknown schema/pack/template, ID collision, bad relationship/cycle/fork, consumed-root mismatch, byte/hash/MIME/JPEG/snapshot/PDF mismatch, and insufficient capacity. Every case rejects before live mutation and removes only its owned stage.
- Recovery/compatibility truth: S6.3 introduces no restore journal, pointer switch, generation install, union, migration, repair, or startup recovery. Existing current generation, reports, media, pending regeneration, failed Retry, diagnostics, commerce, and user-exported package remain byte-for-byte unchanged.
- Accessibility/UI: summary uses the existing Worklight design tokens and semantic controls, logical focus/order, non-color status, and at least 44×44 controls at every Dynamic Type category. Prevent duplicate copy/validation on double activation. Test-only summary injection must not create a shipping navigation route or claim restore success.
- Forbidden behavior: live ModelContext/container mutation; new generation creation/install/open; current/retired pointer or journal creation; union/replacement; partial import; automatic repair; migration; newest-directory guess; ZIP/archive dependency; entitlement/diagnostic import; external package mutation; backend/cloud/account/sync; schema/model/project/capability/permission change; S6.4+ route/progress/recovery; signing, deployment, or release.

## Environment and exact selector

- Route / repository / refs: Windows authoring → exact GitHub Actions macOS verification; `palatis3/AssetRounds / public / main / phase/s6-data-rights`; never run or claim Windows Xcode/Simulator results.
- Required posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Runner / Xcode / project: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer / FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S6.3","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S6_3BackupValidationTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S6_3BackupValidationUITests"]}` plus exactly one LF; 347 UTF-8 bytes, no BOM; SHA-256 `BFB97B3FF1BC13B36ED001D9CB26B2762D49C81F54A586464114272621DB5F18`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, and UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download. Force-push, merge commit, PR, ref rewrite/delete, main mutation before accepted S6.6 boundary integration, settings/secrets, signing, TestFlight/App Store, deployment/release, and S9.2/S9.3 are forbidden.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift`
- `FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift`
- `FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift`
- `FieldEvidenceApp/Features/Shell/AppShellView.swift`

Test paths:

- `FieldEvidenceAppTests/S6_3BackupValidationTests.swift`
- `FieldEvidenceAppUITests/S6_3BackupValidationUITests.swift`
- `FieldEvidenceAppTests/Fixtures/S6_3V4BackupPackageV1.json`
- `FieldEvidenceAppUITests/Fixtures/S6_3V4BackupPackageV1.json`

Standing selector exception:

- `Scripts/ci-selection.json`

No other implementation, model, project, resource, fixture, script, workflow, authority, or documentation path is allowed during S6.3 implementation. Existing export DTO/encoder, media validators, snapshot/report validators, sign-pack registry, canonical JSON, anchored file helpers, generation authority, design tokens, and fixtures may be read and reused without editing. Append-only `docs/execution/HANDOFF.md` remains separately authorized bookkeeping after accepted evidence.

## G0 and transition

- Fresh G0 must prove clean `phase/s6-data-rights`, `A^=M`, exact one-commit HANDOFF-append-plus-CURRENT_TASK `M..A`, remote phase=A, remote main=P, all pins, accepted S6.2 exact-head run/artifact, accepted S6.2 selector byte-exact, and the eight-production/four-test expanded envelope inside the default 10/5 cap.
- After G0, replace only `Scripts/ci-selection.json` with the frozen S6.3 object, then implement exactly this card. Candidate recovery follows the persistent evidence-driven direct-child loop without weakening acceptance or expanding paths.
- After accepted exact-head S6.3 CI, read `KNOWN_BUGS.md`, append the immutable card HANDOFF, and—only if fresh refs still match—commit/push exactly that append plus immediate-next S6.4 `CURRENT_TASK.md`; then run fresh S6.4 G0. Do not mutate `main`.

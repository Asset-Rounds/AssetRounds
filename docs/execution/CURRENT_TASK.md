# Current Task

## Program and card

- Phase / branch / card / global order: `S3 / phase/s3-check-runner / S3.4 / 8 of 36`.
- Card heading: `### S3.4 — Resume, mutation idempotency, and finalization recovery`.
- Position / boundary / immediate next card: `4 of 7 / phase boundary no / S3.5`.
- Program autopilot / phase autopilot / exact S3 span / boundary integration: `enabled through accepted S9.1 / enabled / S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7 / yes at S3.7 only`.
- Frozen phase→branch→card map: `S0→phase/s0-foundation→S0.1; S1→phase/s1-shell-design→S1.1; S2→phase/s2-persistence-signs→S2.1,S2.2; S3→phase/s3-check-runner→S3.1,S3.2,S3.3,S3.4,S3.5,S3.6,S3.7; S4→phase/s4-reports→S4.1,S4.2,S4.3,S4.4,S4.5; S5→phase/s5-work-recheck→S5.1,S5.2,S5.3,S5.4; S6→phase/s6-data-rights→S6.1,S6.2,S6.3,S6.4,S6.5,S6.6; S7→phase/s7-commerce→S7.1,S7.2,S7.3,S7.4,S7.5; S8→phase/s8-quality→S8.1,S8.2,S8.3,S8.4; S9→phase/s9-release→S9.1`.
- End condition: accepted exact-main S9.1; S9.2 signing/TestFlight and S9.3 App Store submission remain owner-only.

## Predecessor and authority state

- Immutable S3 phase-main base: `P=7d135aaddd0bdc50168552b0610f04adc1703506`.
- Accepted S3.3 integrated/card base: `M=E=I=a728f8fe50e016e190074b6a5f4faf104f10c278`; there was no product correction or distinct infrastructure verification head K.
- Predecessor exact-head evidence: run `31646855404`, job `94282347565`, succeeded at exact `phase/s3-check-runner@M` with F25/UI enabled; artifact `ios-ci-31646855404-1`, ID `9161394537`, size `1749211`, API/raw ZIP digest `sha256:4ce3bafb53ede4c306cdaa8fc0e8ad605b5747218d4024622dc9fa6256a6ae4b`; `SHA256SUMS.txt` SHA-256 `3CA6E8E9252E1D8215392BAC79686E8347478114FB00D7962766421D7C8E3A1E`; all 97 payloads independently matched; `ui-final.png` SHA-256 `31C62BAA06E31417339D0764F1D4501365BB1BA137395E20D46DD9E3F270BC0D`. Runner `macos26` image `20260728.0273.1`, Xcode 26.6 `17F113`, iPhone 17/iOS 26.5, UDID `FC5FEF2A-E933-4515-AAEF-C9FC16651D0B`; setup `66/300` s, readiness `314/900` s, setup+artifact `67/300` s, total `782/4500` s.
- Task-start authority head `A`: `OBSERVE AT POST-COMMIT G0; never self-record its SHA here`.
- Required `M..A`: one direct-child same-phase transition commit changing exactly the append-only `docs/execution/HANDOFF.md` S3.3 entry plus this immediate-next `docs/execution/CURRENT_TASK.md`.
- Construction state: immediately before transition, remote `phase/s3-check-runner=M` and remote `main=P`; commit/push only the two authority paths, then require clean index/worktree/untracked state and fresh G0.

## Pinned authority

- Build plan: `docs/product/BUILD_PLAN_V4.md` / `23DAAB390AF917CBE91C3044E4906F3FBF8D67D2FDFC6BC9BDE985D984F37BBD`.
- S3.4 plan anchors: `## 6. Core workflow and state truth`; `## 10. Storage, crash consistency, and one-off bug prevention` (lifecycle/storage rules, evidence-bundle launch reconciliation, exact `FinalizationIntentV1` recovery matrix); global execution anchors remain `## 11`, `## 16`, and `## 18`.
- Runbook: `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md` / `41622B8AE241FDFCBA3A03A430D27069A29DBE39EB508C6E155D687BA8A6AA79`.
- Execution contract: `docs/execution/CODEX_EXECUTION_CONTRACT_V4.md` / `9E7F3ABD2CC6FB15F33E4E56C95474BFEAC79C7148D7D125C75FBF88DB9F8A93`.
- Workflow: `.github/workflows/ios-ci.yml` / `9FFEA51ADB2620B01FE250412716487F6102DAC7E93AEA0471943AF66C1BC2AC` / `workflow_dispatch`.
- Accepted generalized UI exporter: `Scripts/ui-smoke.sh` / `6304A318EE046B6B19F4FDDC43BB143F9B21E8150B9D332E449B87A0182D4CDB`.
- Selector schema path: `Scripts/ci-selection.json`; at G0 it may remain accepted S3.3 LF SHA-256 `567B68707B18B9A9CC719CB4A176CF60B8184F94E0EF70740B03E18FDADCE7DA`. Its first support mutation replaces it with the exact S3.4 object below, LF SHA-256 `38EE4F0A75FD81EF6468907034757DEBD65ADA2B39A582CF46A52397DD1601CC`.

## Outcome and acceptance

- Outcome: make the existing original-check runner and S3.3 finalization authority replay-safe and cold-launch recoverable. Relaunch resumes the exact persisted draft step; exact begin, evidence-acceptance, and finalization mutation replay returns the already-authoritative draft/evidence/finalization result rather than creating a second row, bundle, Packet/root, Report, Issue, or snapshot.
- Draft resume: the sole valid original-check draft and its persisted `draftStepKey` remain authority. A force-quit after accepted wide evidence reopens at close with the same EvidenceFile ID, exact original/thumbnail relative paths, byte counts, and hashes; no capture byte is regenerated, recounted, or replaced.
- Idempotent mutation: exact begin replay returns the prior sole draft. Exact evidence replay for the same evidence authority returns the prior promoted bundle/EvidenceFile and resulting step only when every frozen ID/path/count/hash/purpose fact matches; collision or mismatch fails closed. Exact finalization replay for the same mutation returns the identical record/Packet/report/root and optional Issue authority, including crash-after-save-before-phase-write, and never regenerates IDs, instants, payload, snapshot, or diagnostics authority.
- Launch ordering: after pointer/current-generation open and before feature writes, reconcile finalization first through the existing `StartupRouter` checkpoint. Unknown/malformed/noncanonical intent, unsafe or mismatched path/ID/generation/payload/hash/bytes, invalid row cardinality, committed rows without valid final snapshot, or any ambiguous state routes to exact `finalization_inconsistent` maintenance and does not guess or mutate unrelated data.
- `prepared` matrix: valid staging plus absent final resumes exact promotion; valid final with absent staging advances to `snapshot_promoted`; valid byte-identical staging plus final removes only matching staging and advances; neither removes only the matching intent and leaves the draft resumable only when zero database rows carry that mutation ID. Any mutation row in the neither case, or any mismatched or unexpected bytes/presence, reaches maintenance.
- Later-phase staging rule: at `snapshot_promoted` and `database_committed`, the named staging path must be absent or contain the exact intent-owned bytes identical to the verified final snapshot; exact identical owned staging is removed during that phase's cleanup. Any other staging type, bytes, path, hash, or presence state reaches maintenance; recovery never normalizes it by guess.
- `snapshot_promoted` matrix: valid final bytes are mandatory. The unique mutation ID either proves the exact frozen database transaction already committed or permits one commit of that exact payload only while all frozen Packet/Issue/draft preconditions match. Failed preconditions remove only the matching intent-owned final snapshot and intent and leave the draft retryable; more than one matching mutation row, partial/mismatched rows, or invalid snapshot reaches maintenance.
- `database_committed` matrix: exactly matching committed rows and exact final snapshot path/bytes/hash are mandatory before removing the matching intent. A crash after the one model save but before the phase write is recognized by the unique mutation ID and advances/cleans without a duplicate save. Unknown phase, mismatched IDs/hashes, missing required row/file, or more than one row per mutation reaches maintenance.
- Evidence launch reconciliation remains bounded to existing runner media: remove abandoned `.staging/evidence/<id>` only when a matching valid final bundle exists or no EvidenceFile row exists; remove a final evidence bundle only when no row exists; if a row exists but its exact regular nonsymlink final original/thumbnail path/count/hash/canonical JPEG contract is missing or mismatched, route to `media_inconsistent`. Never scan or repair outside the current generation.
- GOLDEN: force-quit after wide resumes at close with the same file authority; two exact Save/finalize submissions return identical record, packet, report, stable root, snapshot path/hash, optional issue result, and one completed mutation with no duplicate row/file/diagnostic authority.
- ALT-1: parameterized `prepared|snapshot_promoted|database_committed` stage/final/row presence cases produce only a resumable draft or exactly one complete report transaction; every mismatched, malformed, partial, duplicate, unsafe, or unknowable case reaches maintenance without orphan, duplicate, deletion guess, newest-generation guess, or unrelated cleanup.
- Forbidden behavior: S3.5 capacity/write/move/database fault-injection framework or generalized failure seams; event log, generic mutation bus, repository/job/recovery registry; PDF bytes/render/retry/detail/share/export; camera/permission/PhotosPicker; CNV, work, recheck, correction, deletion, backup, restore, erase, access/paywall/StoreKit; new model/schema/project/package/capability/permission/remote delta; broad filesystem scan, guessed generation, repair UI, or adjacent recovery behavior.

## Environment and exact selector

- Route / host: Windows authoring → GitHub Actions macOS verification; never run or claim local Windows Xcode/Simulator results.
- Required tool posture: `sandbox_mode=danger-full-access / approval_policy=never / command network enabled`; trusted repository configuration active; XcodeBuildMCP and owner-operated Mac unnecessary.
- Repository / visibility / default / phase: `palatis3/AssetRounds / public / main / phase/s3-check-runner`.
- Runner / Xcode / developer dir: `macos-26 / Xcode 26.6 Build version 17F113 / /Applications/Xcode_26.6.app/Contents/Developer`.
- Project / scheme / configuration / deployment: `FieldEvidenceApp.xcodeproj / FieldEvidenceApp / Debug / iOS 18.0`.
- Simulator selector: `iPhone 17 / iOS 26.5`; resolve exactly one ephemeral-job UDID.
- Tier / UI input: `P12 / run_ui_smoke=true`.
- Exact selector: `{"schemaVersion":1,"taskID":"S3.4","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S3_4ResumeRecoveryTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S3_4ResumeUITests"]}`.
- Exact commands: `bash Scripts/run-with-timeout.sh 600 bash Scripts/build-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/test-smoke.sh`; `bash Scripts/run-with-timeout.sh 900 bash Scripts/ui-smoke.sh`.
- Required evidence: nonempty boot/build/unit/UI logs; Build, UnitTests, UISmoke result bundles; terminal in-app screenshot; selection/runner/Xcode/Simulator/budget evidence; verified relative `SHA256SUMS.txt`.
- Allowed GitHub methods: read/fetch/ref/run/workflow/artifact inspection; exact-path staging/commits; non-force phase push; named workflow dispatch on exact phase ref with `run_ui_smoke=true`; exact-run observation/download; after green, HANDOFF plus immediate S3.5 transition only. Forbidden: force-push, merge/main mutation before S3.7, PR, ref rewrite/delete, repository/settings/secret mutation, signing, TestFlight/App Store, deployment/release, S9.2/S9.3.

## Exact allowed implementation paths

Production paths:

- `FieldEvidenceApp/Domain/Workflow/FinalizationContracts.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`
- `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`
- `FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift`

Test paths:

- `FieldEvidenceAppTests/S3_4ResumeRecoveryTests.swift`
- `FieldEvidenceAppUITests/S3_4ResumeUITests.swift`

Standing support exception:

- `Scripts/ci-selection.json`

`docs/execution/HANDOFF.md` is append-only post-green bookkeeping and is not part of the implementation commit. No other path may change.

## Execution

1. Fresh G0 proves `A^=M`; `M..A` is exactly one append-only HANDOFF plus CURRENT_TASK transition commit; remote main=P and remote phase=A; carried map/pins/public repository/environment/tool/method posture are byte-identical; selector remains accepted S3.3; no other path is dirty.
2. Replace selector first, implement only allowed paths, run structural/static Windows checks, explicitly stage task paths, and commit direct-child I.
3. Push exact phase ref non-force and run the one-at-a-time persistent P12 loop. Accept only green exact-head CI with complete checksum-verified unit/UI/evidence artifacts; each terminal failure permits only the smallest diagnosed direct-child correction before fresh verification.
4. After accepted S3.4 evidence, append HANDOFF and transition only to immediate-next S3.5 when remote phase still equals accepted head. Do not mutate main.

## Definition of done

- Exact green S3.4 evidence: relaunch after wide resumes close with identical durable evidence; begin/evidence/finalization replay returns prior authority; double Save yields identical IDs/files and one transaction; every exact finalization phase/presence/row case resolves to a resumable draft, one complete report, or `finalization_inconsistent` maintenance without orphan/duplicate/guess; current-generation evidence reconciliation preserves valid rows/bundles and fails closed on mismatch.
- Handoff records required evidence; remote phase equals accepted verification head, then continue only with S3.5.

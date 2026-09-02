# V4 Codex Implementation Runbook — Execute, Do Not Replan

Status: canonical execution catalog for the device-local V4 iPhone app.

Install this exact file as `docs/execution/V4_IMPLEMENTATION_RUNBOOK.md`. It contains **42 strictly ordered Codex coding cards plus two owner-only release gates**. One persistent `/goal` completes the coding program through S10.6 while every card remains separately scoped, committed, and CI-verified. Program autopilot performs verified non-force fast-forward `main` integration and exact-main CI at each phase boundary. Product and hosted-CI failures remain inside an evidence-driven retry/correction loop with no numeric ceiling; that loop never expands product-card scope or weakens acceptance.

## 1. Authority and use

Repository authority, highest first:

1. `docs/execution/CURRENT_TASK.md` for one active card, owner-completed at S0 start or program-autopilot-completed at a later phase start, and eligible only for the closed same-phase or boundary transition after accepted evidence.
2. Exact SHA-256-pinned `docs/product/BUILD_PLAN_V4.md` for product truth.
3. This exact SHA-256-pinned runbook and its selected card for implementation order, files, acceptance, and tests.
4. Existing code and tests as baseline evidence only.

The catalog is not blanket authority. `CURRENT_TASK.md` names exactly one current card, pins this file, freezes the exact program phase/branch map and same-phase span, and sets transition/integration flags. Codex may not combine cards, skip a predecessor, repair or pre-implement a later feature, force-push, sign, upload, deploy, or submit. Phase autopilot grants immediate-next-card bookkeeping after accepted exact-head CI. Program autopilot grants only verified phase-close fast-forward integration, exact-main CI, and the frozen next phase's first-card authority. One implementation checkout and one current card are active at a time.

The build plan remains product truth and its phase-summary table is aligned to this catalog. S7.1 installs the nonpurchasable commerce processor and shared local fixture; S7.2 is the first purchase UI. Neither card changes the frozen offer or release gates.

## 2. Fixed launch decisions

- One-person, device-local iPhone app for illuminated-sign field checks; internal target/scheme `FieldEvidenceApp` remains brand-neutral.
- Author on Windows. Ordinary cards compile, automated test, and prove the Simulator only in the task-named GitHub-hosted macOS workflow. The sole S10.4 exception is the owner-authorized hybrid Build Hub route after a nonaccepting same-shard GitHub-to-Bitrise exact-environment equivalence gate: its one exact-head, complete checksummed `build-for-testing` `xctestrun` plus `Build/Products` payload may be reused only by verified `test-without-building` consumers; no consumer may rebuild, fall back, mix heads, or share Simulator/evidence state. Bitrise may formally satisfy only current-runtime `default-light` and `default-dark` after equivalence; GitHub formally covers every minimum-profile shard, including iPhone SE (3rd generation) / iOS 18.0 build `22A3351`. Screenshots remain independently checksummed per provider and are not byte-compared across providers. Physical proof is owner-run TestFlight.
- Minimum iOS 18.0. At this freeze, revalidate `macos-26`, Xcode 26.6 build 17F113, iOS 26.5, and iPhone 17 at S0; never silently substitute.
- SwiftUI, SwiftData, app-owned JPEG media, canonical JSON snapshots, deterministic Core Graphics/PDFKit PDF, and direct StoreKit 2.
- No backend, app account, sync, CloudKit, Firebase, Supabase, RevenueCat, Stripe, remote config, third-party production SDK, web surface, AI diagnosis, notification, public second vertical, or annual SKU.
- Navigation is Signs, Reports, and a Settings gear. Production bundles only `IlluminatedSignPack@1`; an exterior-light pack is test-only.
- Offer intent is one StoreKit-localized monthly product at a U.S. `$59.99` base-price hypothesis, 14-day introductory offer when eligible, one concurrent live-sign slot while fewer than three completed free report roots are counted, and a monotonic three-root limit between Erase All operations.
- App Store Connect SKU creation/activation requires the recorded six-of-ten exact-offer commitment gate. Local `.storekit` development does not require or satisfy that gate.
- Apple Billing Grace is fixed at 16 days for paid-to-paid renewals; Family Sharing is off. These are confirmations, not owner-selectable alternatives.
- Build only the card-named launch checks. Do not add a generic framework, adversarial matrix, speculative abstraction, unrelated cleanup, or future capability.

## 3. Card, phase, and program-autopilot hydration

At S0 phase start, `CURRENT_TASK.md` freezes program autopilot, the exact phase/branch map, phase autopilot, and the ordered S0 span. Later phase starts are hydrated by program autopilot only after the preceding phase's accepted exact-main verification/phase-close head, including an accepted infrastructure `K` when the standing lane applies. For any transition, Codex hydrates only the immediate next runbook card and uses this closed rule:

- Carry forward byte-for-byte the repository/visibility/base identity; immutable program-autopilot state and exact S0–S10 phase/branch map; plan/runbook/workflow identity; runner/Xcode/deployment/project/scheme/configuration; Simulator selector; Full access posture; allowed method set/prohibitions; and final S9.2/S9.3 owner boundary after S10.6. Freeze phase-main base `P` for every card in a phase: `P=B` for S0 and the prior accepted exact-main phase-close SHA thereafter. Inside a phase also carry phase ID/branch, phase-autopilot state/span, and flags. At an exact boundary, change only phase ID/branch/span/flags and `P` to the next frozen values. Codex may never alter the program map.
- Set current card ID/order/position/boundary/tier/selectors from the immediate runbook card. Within a phase set `M` to the prior accepted implementation or verification head required by CURRENT_TASK and expected `M..A` to HANDOFF plus CURRENT_TASK. At phase start set `M=P` and expected `M..A` to CURRENT_TASK alone; include predecessor main run evidence. Historical S0.1/S0 recovery evidence remains immutable. For an infrastructure recovery, preserve product implementation `E`, set failed verification base `F`, keep candidate `K` as `OBSERVE AT POST-COMMIT G0`, and declare exact `F..K` lane paths. Card-specific UI mode, selector semantics, product commands, paths, delta, and acceptance remain frozen; only a causally diagnosed CI-harness scheduling/evidence/watchdog correction and its exact pins may differ.
- Copy the card's exact outcome, delta, GOLDEN, ALT-1, terminal, next card, and named exclusions. Enumerate the smallest concrete fully expanded individual repository-relative file paths inside the card's named categories and cap, reusing existing paths when possible. Globs, directory roots, brace/set expressions, and `/**` are forbidden in hydrated tasks. A cap may exceed the default only when this frozen selected runbook card explicitly states the override; CURRENT_TASK cannot self-raise it. Optional/speculative paths remain forbidden.
- Never invent a package, permission, schema field, product decision, selector, fixture, public copy, or release value. If more than one materially different path/file shape is plausible or a required fact is absent, retain the current card, gather repository/Git/GitHub evidence, continue every independent in-card action, and hydrate only facts uniquely implied by frozen authority. An unresolved value is recorded explicitly rather than silently guessed; it does not consume program authority or erase completed evidence.
- S0.1 alone uses bootstrap SHA `B` because no iOS project CI exists yet. At phase start, owner- or program-autopilot-prepared `A` normally changes only CURRENT_TASK. Historical S0.1 authority/recovery, `I3`, HANDOFF-only `C`, and authority-only `R` remain recorded facts. A later ordinary same-phase `A` must parent the accepted prior implementation/verification head and contain exactly HANDOFF plus CURRENT_TASK; next-phase `A` parents the accepted exact-main phase-close head, contains CURRENT_TASK only, and sets `P=M` to that head. The standing infrastructure lane may create direct-child `K` with only its declared allowlisted subset and exact repins in the same commit. Fresh G0 proves immutable carry-forward fields, exact lane ancestry/diff, protected-tree equality, and frozen selector/tier. It validates expected selector/tier while allowing `ci-selection.json` absent for initial S0.1 or still equal predecessor; after G0, replacing it is the first implementation-support mutation only for an ordinary card whose CURRENT_TASK authorizes a selector change.

Never place passwords, 2FA codes, bank/tax details, `.p8`, `.p12`, provisioning profiles, private customer data, or release secrets in source, chat, ordinary CI, logs, screenshots, or artifacts.

## 4. Card and phase lifecycle

1. The first card of S0 starts on its frozen branch. Each later phase starts on its frozen branch created by program autopilot from accepted green exact-`main`; later cards continue the same phase branch from the prior accepted verification head plus one transition commit.
2. For each card, Codex performs fresh read-only G0: verify `P`, ancestry, exact `M..A`, selected hashes/card, program/phase map, dirty paths, envelope, Full access posture, pins, selectors, and watchdog tier. A discrepancy triggers reread, fetch, history inspection, waiting, or the authorized mechanical evidence/repin update. It is not an approval-message gate. Infrastructure post-commit G0 proves direct parent, exact declared diff, clean state, matching pins, protected product/selector equality, expected remote refs, and failed-run diagnosis.
3. Codex implements only the active card and creates direct-child implementation `I`. Product/card success requires a green exact-head run with complete required evidence. A diagnosed product, compiler, test, or acceptance failure creates one direct-child task-scoped correction changing only the card's allowed paths and required authority evidence/pins, then verifies again. Successive heads are `I`, `I2`, `I3`, and so on with no numeric correction or rerun ceiling. The first exact-green product head is accepted `E`; no correction weakens outcome, GOLDEN, ALT-1, selectors, tests, evidence, or acceptance.
4. CI candidates are append-only and one-at-a-time per exact workflow/ref/head. If any candidate is green with complete evidence, accept it. If one is queued or running, wait. Otherwise inspect every terminal candidate/log/artifact and dispatch exactly one new `workflow_dispatch` candidate at the same branch ref, exact head, inputs, runner/toolchain/Simulator selector, and tier. Every redispatch receives a new run ID; never use Actions rerun on a failed run ID. Candidate count, repeated signature, missing artifact, or watchdog expiry never consumes authority.
5. For a diagnosed hosted-runner, pinned-toolchain/runtime, exact-Simulator, Actions service/transport, or lane-harness failure, either redispatch the same exact head on a fresh runner or create one direct-child `K(n+1)` with one smallest diagnosed operational correction. K may change only required CURRENT_TASK evidence/pins and the smallest causal subset of `.github/workflows/ios-ci.yml`, `Scripts/build-smoke.sh`, `Scripts/test-smoke.sh`, `Scripts/ui-smoke.sh`, and `Scripts/run-with-timeout.sh`. Preserve product/project/test/fixture/asset bytes, selector semantics, pinned environment, exact product commands/destinations, timeout exit behavior, evidence/checksum/upload enforcement, and raw aggregate accounting. K indices, correction count, repeated/overlapping failure/repair labels, hashes, and trailers are provenance rather than consumption gates. When evidence is insufficient, gather another exact-head candidate or add one non-accepting diagnostic K.
6. On a non-boundary card after green evidence, Codex appends HANDOFF. When phase autopilot is enabled and the immediate next runbook card is inside the authorized span, apply Section 3's closed hydration rule and create one transition commit containing exactly that HANDOFF append plus next CURRENT_TASK. Re-fetch before non-force push, require remote phase to equal accepted verification head `V` (`E` normally, exact green K when distinct), push, verify the new ref, and run fresh G0. Unexpected movement triggers read-only ancestry/provenance diagnosis and valid-lineage recovery; never force or silently reconcile unrelated history.
7. On a final card after green implementation evidence, append HANDOFF and create/push phase-close `C`. Re-fetch and prove refs, then apply Steps 4–5 on the phase ref at C or a later direct-child recovery head until that exact phase-close/verification head is green. Only then advance `main` by verified non-force fast-forward from phase base `P` to that exact green head, or resume if main already equals it. Reuse a matching exact-main success, wait for an active candidate, or use Steps 4–5 until exact-main CI is green. A product failure at phase-close or exact-main keeps the boundary card active for successive scoped product correction heads and repeated phase/main verification; prior HANDOFF entries remain append-only. Then create/resume only the frozen next phase branch, hydrate its first card, and run fresh G0. After green exact-main S10.6, report the accepted head/run and end coding for owner-only S9.2/S9.3.
8. Watchdogs are exact, non-accepting cleanup controls rather than authority limits. Simulator readiness is `900` seconds; tier values are the exact Section 6 compatibility-label values; job watchdog is 90 minutes; concurrency does not cancel an in-progress candidate. A timeout or missing artifact remains non-green and feeds Steps 3–5. Failed run IDs remain historical and are never rerun by ID.
9. Current S0 bridge: retain `E=I3=ac310dd37700d65165200f742aaec1d48d0a34d6`, HANDOFF-only `C=15348e92466a79efd02bfb71f5ffee043e615829`, authority head `R=1e0322cc072fda28718468bcd1b0dbe1f5d0accc`, failed main runs `31567299022` at C and `31571125674` at R, K1 `0da62482db7e3f90742876ef05574de9e9569e32`, K2 `400f8827f5451b9a44f4d846340b51377554069d`, and their failed runs as immutable provenance. K3 `e569951909c2ee8aff4253bae0d442550c229a16` passed exact-head phase run `31590956549`. Exact-main K3 run `31591804256` failed only the historical 300-second Simulator-readiness watchdog after the unchanged product build passed. Direct-child K4 installs the persistent recovery policy and Section 6 watchdog values without changing protected product/project/test bytes. Verify K4 or a later direct-child recovery head on phase and exact-main through Steps 4–5 until green. Accepted K becomes S0 phase close and S1 `P=M`; I3 remains product evidence. Do not amend the completed historical HANDOFF.

Every card gets one accepted product implementation and exact-head verification. Every phase gets non-force fast-forward integration and exact-main verification. A distinct infrastructure verification head may move verification without changing product evidence. One persistent program goal runs sequentially; no two cards write the checkout concurrently.

## 5. Stable repository map

S0.1 creates file-system-synchronized groups so later Swift files do not repeatedly edit `project.pbxproj`.

```text
FieldEvidenceApp.xcodeproj/
FieldEvidenceApp/
  App/
  DesignSystem/
  Domain/Models/
  Domain/Packs/
  Domain/Rules/
  Domain/Backup/
  Features/Shell/
  Features/Sample/
  Features/Signs/
  Features/CheckRunner/
  Features/Reports/
  Features/Issues/
  Features/DataRights/
  Features/Subscription/
  Features/Settings/
  Infrastructure/Persistence/
  Infrastructure/Media/
  Infrastructure/Reporting/
  Infrastructure/Backup/
  Infrastructure/StoreKit/
  Infrastructure/Diagnostics/
  Resources/Packs/
  Resources/Assets.xcassets/
  PreviewSupport/
FieldEvidenceAppTests/
FieldEvidenceAppUITests/
TestFixtures/Photos/
TestFixtures/Packs/
TestFixtures/Backups/
TestFixtures/Failures/
TestFixtures/StoreKit/FieldEvidence.storekit
Scripts/
  build-smoke.sh
  test-smoke.sh
  ui-smoke.sh
  run-with-timeout.sh
  ci-selection.json
Release/
```

No project generator, service locator, command bus, reducer framework, repository matrix, workflow DSL, remote pack engine, or marketplace.

## 6. Exact CI tiers

`Scripts/ci-selection.json` is the single task-to-CI selector. It has exactly these keys and types; this P12 object is the canonical shape:

```json
{
  "schemaVersion": 1,
  "taskID": "S0.1",
  "tier": "P12",
  "runUISmoke": true,
  "setupArtifactTimeoutSeconds": 300,
  "buildTimeoutSeconds": 600,
  "testTimeoutSeconds": 900,
  "uiTimeoutSeconds": 900,
  "totalBudgetSeconds": 3300,
  "unitTestSelectors": ["FieldEvidenceAppTests/S0LaunchTests"],
  "uiTestSelectors": ["FieldEvidenceAppUITests/S0LaunchUITests"]
}
```

Unknown/missing keys, wrong types, duplicate selectors, malformed selector prefixes, or a blank `taskID` fail before build. After targeted tests, every configured unit/UI selector must resolve to at least one non-skipped executed Test Case in its matching `.xcresult`; otherwise evidence validation marks the run failed before checksum calculation and diagnostic upload. Unit selectors are nonempty and begin `FieldEvidenceAppTests/`. `N8` has `runUISmoke=false`, `uiTimeoutSeconds=0`, and an empty UI array. `P12`/`F25` have `runUISmoke=true` and exactly one bounded selector beginning `FieldEvidenceAppUITests/`. The manual workflow input `run_ui_smoke` must equal the JSON value. Tier IDs are compatibility labels, not literal minute counts. The five timeout values must exactly match one closed tier below; setup/evidence time is part of the total, not extra.

| Tier | Total | Setup/artifacts | Build | Targeted unit | Targeted UI | UI/accessibility rule |
|---|---:|---:|---:|---:|---:|---|
| `N8` | 2400 s | 300 s | 600 s | 900 s | 0 s | UI selector must be empty; UI and accessibility execution are rejected |
| `P12` | 3300 s | 300 s | 600 s | 900 s | 900 s | Exactly one bounded XCUITest class; touched-control semantics only |
| `F25` | 4500 s | 300 s | 900 s | 1200 s | 1800 s | One fresh-install milestone class including its named accessibility checkpoints |

S0 creates `run-with-timeout.sh`; it accepts a positive integer ceiling followed by one command and its arguments, launches that command in its own process group, forwards the exit status, and on expiry sends TERM, waits at most five seconds, sends KILL if needed, and exits 124. The workflow validates selector shape before build and validates selector resolution/execution from the resulting `.xcresult` after tests, wraps build/test/enabled-UI scripts with those watchdogs, and leaves a run non-green when elapsed setup+lane-authorized infrastructure readiness+build+test+UI+evidence-validation/checksum time exceeds the total. Exact-UDID readiness has its own 900-second watchdog. Artifact upload is outside the selected total but remains inside the 90-minute job watchdog. Workflow concurrency uses `cancel-in-progress: false`.

The scripts must write these exact baseline required artifacts under `CI_ARTIFACT_DIR`: nonempty `build-smoke.log`, directory `Build.xcresult`, nonempty `test-smoke.log`, and directory `UnitTests.xcresult`; enabled UI additionally requires nonempty `ui-smoke.log`, directory `UISmoke.xcresult`, and nonempty `ui-final.png`. A lane-authorized infrastructure diagnostic may be required only in addition to this baseline and must be nonempty and checksummed. The workflow verifies them before upload and creates `SHA256SUMS.txt` with relative paths from inside the artifact root. `N8` never accepts a placeholder UI selector or accessibility option; P12/F25 never become a broad UI suite. A timeout is non-accepting evidence for the persistent recovery loop; it consumes no retry or correction authority.

For P12/F25, every touched primary control has a label, trait, logical order, non-color state, 44-point target, and named focus behavior; card acceptance checks only the touched route. S10.5 records real camera quality and owner-observed physical accessibility for the branded candidate; signing/upload/release verification remain S9.2.

## 7. Frozen implementation contracts

### 7.1 Exact local schema and evaluation authority

V4 has exactly seven SwiftData models. Every model has `schemaVersion=1` and a stable lowercase-canonical UUID `id`; **there is no `Observation` model, observation array, generic answer value, or hidden form schema**.

1. `Site` — `id`, `schemaVersion`, `label`, nullable `address`, nullable confirmed-IANA `timeZoneID`, `createdAt`, `updatedAt`.
2. `Asset` — `id`, `schemaVersion`, `siteID`, `packID`, `packSchemaVersion`, `packContentVersion`, `label`, `createdAt`, `updatedAt`.
3. `WorkflowRecord` — `id`, `schemaVersion`, `assetID`, nullable `packetID`, nullable `issueID`, nullable `parentRecordID`, immutable `recordRevisionRootID`, nullable `revisesRecordID`, nullable `evidenceSourceRecordID`, `revisionKind=original|clerical_correction`, `stage=check|work|recheck`, `state=draft|completed`, nullable `draftStepKey=wide|close|outcome|review`, `startedAt`, nullable `completedAt`, nullable frozen time fields `observedAtUTC`, `timeZoneID`, `utcOffsetMinutes`, `localDate`, `localTime`, `afterDarkAcknowledgementKey`, `afterDarkAcknowledgementCopy`, `afterDarkAcknowledgementVersion`, `afterDarkAcknowledgementAccepted`, `safePositionAcknowledgementKey`, `safePositionAcknowledgementCopy`, `safePositionAcknowledgementVersion`, `safePositionAcknowledgementAccepted`, `packID`, `packSchemaVersion`, `packContentVersion`, `pdfTemplateID`, `pdfTemplateVersion`, nullable `outcomeKey`, nullable `couldNotVerifyKey`, nullable `couldNotVerifyDisplaySnapshot`, nullable `couldNotVerifyRegistryVersion`, nullable `workPerformedLocalDate`, nullable `workDescription`, nullable `note`, and nullable unique `finalizationMutationID`. PDF template is always `field.evidence.pdf.worklight.v1/1`; all eight acknowledgement fields are null as a group for work and nonnull as a group for check/recheck.
4. `EvidenceFile` — `id`, `schemaVersion`, `recordID`, `purposeKey`, `relativePath`, `mimeType`, `byteCount`, `sha256`, `createdAt`, `thumbnailRelativePath`, `thumbnailByteCount`, `thumbnailSHA256`.
5. `Issue` — `id`, `schemaVersion`, `assetID`, `openedByRecordID`, immutable `labelKey`, immutable `labelDisplaySnapshot`, `status=open|recheck_due|resolved`, nullable `resolvedByRecordID`, `createdAt`, `updatedAt`.
6. `Packet` — `id`, `schemaVersion`, unique immutable `stableRootID`, nullable `currentRecordID`, `evaluationCounted`, nullable `contentDeletedAt`, `createdAt`. A live packet has current record/nondeleted content; a deletion tombstone retains only its packet ID/schema, stable root, evaluation flag, and created/deleted instants and has no Asset relationship.
7. `Report` — `id`, `schemaVersion`, `packetID`, `sourceRecordID`, `snapshotSchemaVersion`, immutable `snapshotRelativePath`, immutable `snapshotSHA256`, `pdfState=pending|ready|failed`, nullable `pdfRelativePath`, nullable `pdfSHA256`, `createdAt`, nullable forward-only `replacesReportID`. Only `pending→ready|failed` and explicit `failed→pending→ready|failed` are permitted; `ready` is terminal and requires matching path/hash/bytes.

A draft has null completion/outcome/mutation/packet; a completed record has one unique mutation ID and nonnull completion/outcome. Originals have `recordRevisionRootID == id` and null revision/evidence-source links. A check has no parent; completed check/recheck has a Packet; work never has one. Completed work requires an Issue, `outcomeKey=work_recorded`, ISO local date, trimmed 1–160-character description, optional trimmed 1–1000-character note, null preflight/CNV fields, and zero/one work photo; work drafts may leave outcome/date/description null. Check/recheck require complete frozen time/acknowledgement groups. Raw check outcomes are `no_visible_issue|visible_issue|could_not_verify`; raw recheck outcomes are `resolved|issue_still_visible|original_resolved_different_issue|could_not_verify`. The three CNV fields are all nonnull only for CNV and all null otherwise; work fields are both null outside work; every nonnull note is trimmed and 1–1000 characters.

Issue records form one exact parent chain. Work starts only from `open` and parents the latest completed substantive record for that Issue. Recheck starts only from `recheck_due` and parents its latest completed substantive record, normally work or a prior CNV recheck. Child Asset/Issue IDs must match that parent, except the one additional Issue opened by `original_resolved_different_issue`. `beginOrResumeDraft(assetID:requestedStage:issueID:)` always returns the Asset's one existing draft before considering a new route; only no-existing-draft may validate and create the requested stage/lineage.

A clerical correction is a completed check/recheck under the same Packet/root. It changes only `note`, points `revisesRecordID` to the immediately prior current revision, points `evidenceSourceRecordID` directly to the original evidence owner, creates no EvidenceFile, and cannot change or create Issue authority.

The free evaluation is derived only from live Assets plus the set of live/tombstoned `Packet.stableRootID` values where `evaluationCounted=true`; there is no second usage ledger or device fingerprint. One live sign is allowed concurrently while fewer than three roots are counted. Whole-sign deletion frees that concurrent slot but never removes counted-root tombstones. Finalizing a new check/recheck root counts exactly once even when PDF later fails; work and corrections do not count. Erase All/uninstall resets this accepted device-local evaluation limitation.

`StoreSessionCoordinator` is main-actor-owned, owns the current `ModelContainer`, and publishes a monotonically increasing UI generation token. There is at most one active draft per Asset.

### 7.2 Canonical snapshot and recoverable finalization

`ReportSnapshotV1` is a closed Codable DTO, never SwiftData. Its exact lexicographically encoded top-level keys are `acknowledgements`, `asset`, `couldNotVerify`, `disclaimer`, `display`, `evidence`, `evidenceSourceRecordID`, `history`, `issues`, `note`, `outcome`, `pack`, `packetID`, `pdfTemplate`, `reportID`, `site`, `snapshotCreatedAt`, `snapshotSchemaVersion`, `sourceApp`, `sourceRecordID`, `stableRootID`, `stage`, and `timeContext`; arrays are never null.

- `AcknowledgementSnapshotV1={accepted,copy,key,version}`; the array is always `[after_dark,safe_authorized_position]`, both accepted.
- `AssetSnapshotV1={label}`; `SiteSnapshotV1={address,label}`.
- `CouldNotVerifySnapshotV1={display,key,registryVersion}`.
- `DisplaySnapshotV1={assetSingular,checkSingular,issueSingular,outcome,stage}` freezes the exact PDF-visible pack/global-registry strings at finalization.
- `EvidenceSnapshotV1={byteCount,createdAt,evidenceID,mimeType,purposeDisplay,purposeKey,recordID,relativePath,sha256,thumbnailByteCount,thumbnailRelativePath,thumbnailSHA256}`.
- `HistoryEntrySnapshotV1={completedAt,couldNotVerify,evidenceIDs,issueIDs,note,outcome,outcomeDisplay,recordID,stage,stageDisplay,workDescription,workPerformedLocalDate}`; both display fields freeze exact pack/global-registry text for that historical record.
- `IssueSnapshotV1={createdAt,display,issueID,key,openedByRecordID,resolvedByRecordID,status,updatedAt}`.
- `PackSnapshotV1={contentVersion,id,schemaVersion}`; `PDFTemplateReferenceV1={id:"field.evidence.pdf.worklight.v1",version:1}`.
- `SourceAppSnapshotV1={build,version}`; `TimeContextSnapshotV1={localDate,localTime,observedAtUTC,timeZoneID,utcOffsetMinutes}`.

`evidenceSourceRecordID` is always `sourceRecord.evidenceSourceRecordID ?? sourceRecord.id`. Current evidence is only evidence whose `recordID` equals that exact effective source; a missing current purpose never falls back to history. Issues are reconstructed at that source-chain cutoff rather than read from later mutable rows and sort by creation/ID. When an issue exists, history contains only completed substantive original check/work/recheck ancestors strictly earlier than the effective source, excludes that source and every correction, and sorts by completion/ID; otherwise it is empty. Every history entry freezes `stageDisplay`/`outcomeDisplay`; raw-key presentation and render-time pack/registry lookup are forbidden. History `issueIDs` are unique lowercase UUID order; evidence IDs use purpose order `wide_context`, `close_detail`, `work_context`, then UUID. Evidence contains each referenced file once: effective-source evidence first, then previously unseen history evidence. Top-level CNV is nonnull only for a CNV outcome. All optional keys are emitted as JSON null.

A correction starts from the immediately prior current Report snapshot, not mutable Site/Asset/Issue rows. It changes only `reportID`, `sourceRecordID`, `snapshotCreatedAt`, `sourceApp`, and `note`; packet/root/effective source, stage/outcome/display, acknowledgements/time, pack/template, evidence, history, issues, and disclaimer remain semantic copies before canonical re-encoding.

Canonical bytes are UTF-8, NFC text, LF, no BOM/indent/trailing whitespace/trailing newline; keys sort lexicographically at every level, `/` is not escaped, UUIDs are lowercase canonical, UTC instants are RFC 3339 with exactly three fractional digits and `Z`, and no floating-point field exists. A checked-in golden fixture plus expected SHA-256 is encoder authority. `SnapshotValidatorV1` recomputes the canonical hash; matches report/packet/source/effective-evidence/root/template/pack relations; rejects duplicate references; confines every path to the current generation; matches every original and thumbnail to its row, decoded canonical JPEG, count, purpose/display, MIME, hash, and bytes; proves current evidence equals the effective-source set; and proves history excludes that source. Rendering receives only the validated snapshot/digest.

`FinalizationIntentV1` lives at `Application Support/FieldEvidenceOperations/finalization/<mutation-id>.json` and has exactly `completedAt`, `finalizationMutationID`, `finalizationPayload`, `finalizationPayloadSHA256`, `generationID`, `packetID`, `phase`, `recordID`, `reportID`, `schemaVersion`, `snapshotCreatedAt`, `snapshotFinalRelativePath`, `snapshotSHA256`, `snapshotStagingRelativePath`, and `stableRootID`; phase is `prepared|snapshot_promoted|database_committed`. `FinalizationPayloadV1` has exactly `issueInsert`, `issueTransition`, `packetAfter`, `packetBefore`, `reportInsert`, and `workflowRecordAfter`; inapplicable inserts/transitions/prior Packet are explicit null, and an issue transition is exactly `{after,before}`. Before promotion S3 freezes the payload/IDs/instants, writes and verifies staging bytes plus both hashes, then atomically writes `prepared`. It promotes the same bytes, advances to `snapshot_promoted`, commits one SwiftData save only while all frozen Packet/Issue preconditions match, advances to `database_committed`, and removes stage/intent.

Recovery is a closed phase-and-presence matrix. At `prepared`: valid stage/no final resumes promotion; valid final/no stage advances; identical valid stage+final removes stage and advances; neither removes intent and leaves the draft; any mismatch opens maintenance. At `snapshot_promoted`, valid final bytes are mandatory; the unique mutation ID proves the exact save already committed or permits the exact frozen save while preconditions match. Failed preconditions remove only the matching intent-owned final snapshot and intent and leave the draft. At `database_committed`, matching rows and final bytes/hash are mandatory before cleanup. A crash after database save but before the phase write is recognized by mutation ID. Unknown phase, mismatched ID/hash, committed rows without valid snapshot, or duplicate mutation rows open maintenance and never guess.

### 7.3 Exact media, storage, and PDF contracts

`MediaContractV1` accepts one still frame from `public.jpeg|public.heic|public.heif|public.png`; animated/multipage and RAW fail. A source is at most 80 MiB, at most 100,000,000 decoded pixels, and 1–16,384 pixels per axis. Decode applies orientation, tone-maps into 8-bit sRGB, composites alpha on white, strips EXIF/GPS/IPTC/XMP/TIFF/orientation metadata, and writes one JPEG at quality 0.90, no upscale, longest edge ≤4096, bytes ≤32 MiB. The thumbnail uses the same pipeline at quality 0.75, longest edge ≤512, bytes ≤2 MiB. Only structural JFIF plus the selected sRGB ICC profile may remain. Restore rejects noncanonical media rather than re-encoding it. Durable evidence is `.jpg`/`image/jpeg` only.

Acceptance writes and verifies `.staging/evidence/<id>/{original.jpg,thumbnail.jpg}`, atomically renames that one directory to `evidence/<id>/`, then commits the EvidenceFile row with both byte counts and hashes. Backup maps the unchanged live bytes to `media/<id>.jpg` and `thumbnails/<id>.jpg`. After the current store validates, launch removes an abandoned stage only when a matching valid final bundle exists or no row exists; removes a final bundle only when no row exists; and opens maintenance when a row's file/path/count/hash/decoded JPEG is missing or mismatched. It never deletes by age or unvalidated scan. Check/recheck requires exactly one wide and close; CNV permits zero/one already accepted of each; work permits zero/one work-context only.

One `StoragePreflightService` uses important-usage capacity for the actual target volume and requires the operation estimate plus a 64 MiB reserve: evidence acceptance 68 MiB; PDF twice referenced-image bytes plus 32 MiB; backup export declared payload plus 20%; restore twice declared payload plus 20%. Failure writes no row/file and leaves prior data readable.

`WorklightPDFRendererV1` implements `PDFTemplateV1` (`field.evidence.pdf.worklight.v1`, version 1). Coordinates use the Core Graphics lower-left origin on Letter `612×792`. Geometry is exact: outer margin 42; content rect `x=42,y=72,width=528,height=678`; footer rect `x=42,y=42,width=528,height=18`; 12-point clear gap. Nothing draws outside those rectangles. Canvas is white, print accent `#006D75`, text black, and every status includes plain text.

Only PDF built-in fonts are used: Helvetica-Bold 22/27 title, Helvetica-Bold 15/18 section, Helvetica 10/14 body, Helvetica 8/11 caption, Courier 7/9 footer. Spacing is 18 after title, 12 before section, 6 after heading, 6 between ordinary blocks, and 4 between image/label. Text wraps with Core Text within 528 points. A heading keeps two following body lines; a paragraph of at least four lines splits only on a line boundary with two lines on each page; history rows never split. Deterministic first-pass pagination precedes second-pass drawing.

Current evidence is selected only where `recordID == evidenceSourceRecordID`. Current originals aspect-fit within `528×288`; history uses only validated thumbnails, up to three `160×120` boxes in one row with 12-point gaps. Images are never cropped, tinted, filtered, or upscaled and stay with frozen purpose/date captions. A missing required CNV purpose renders `Not captured — Could not verify`; history never substitutes. Render order is frozen identity/time, current wide, current close, stage/outcome/CNV/note, issues and strictly earlier work/recheck history with thumbnails, disclaimer, then every-page two-line footer with snapshot time/app/pack/template/hash at left and `Page n of N` at right. Formatting is `en_US_POSIX`/Gregorian and uses only snapshot strings, with no database or pack lookup. Metadata uses snapshot time, fixed creator `FieldEvidenceApp PDFTemplateV1`, and no author/subject/keywords. S4.1 renders the same validated fixture twice to byte-identical output on the pinned toolchain.

PDF promotion is deterministic by Report ID. A crash after rename but before `ready` leaves a pending/failed row; startup removes that non-ready final PDF only after validating its expected path. Pending rerenders; failed waits for Retry. Ready is accepted only when path/hash/bytes match. Historical V1 pending/failed reports always use the retained V1 renderer.

### 7.4 Deletion, backup, immutable-generation restore, and erase

V4 exposes no Packet/report delete action. Whole-sign confirmation is exactly `Delete this sign, its photos, and its reports from this app? This cannot be undone. Your free-report count will not reset. Erase All removes the remaining anonymous count.` with **Cancel** and destructive **Delete sign**. `DeletionIntentV1` lives at `Application Support/FieldEvidenceOperations/deletion/<deletion-id>.json` and has exactly `assetID`, `countedPacketTombstones`, `deletionID`, `generationID`, `phase`, `relativePaths`, and `schemaVersion`; paths are unique sorted generation-relative strings and phase is `prepared|database_committed`. One SwiftData save removes the Asset's referentially closed WorkflowRecord/EvidenceFile/Issue/Report lineage, removes the Site only if empty, and replaces counted Packets with content-free tombstones retaining only anonymous IDs/evaluation flag/instants; only then are listed files removed. Recovery cancels a prepared intent while the Asset remains, recognizes a committed tombstone set, and completes exact-path cleanup. No fragment deletion may strand issue/revision lineage.

`V4Backup@1` is a user-selected FileWrapper package with extension `.fieldrecordbackup`; S6.2 uses frozen exported UTI `com.palatis3.fieldrecordbackup`, conforming to `com.apple.package`. Its exact members are `manifest.json`, `records.json`, `media/<evidence-uuid>.jpg`, `thumbnails/<evidence-uuid>.jpg`, `snapshots/<report-uuid>.json`, and ready-only `pdfs/<report-uuid>.pdf`. Export requires storage preflight, a destination confirmation, and the exact sensitive-content warning from the build plan; it makes no encryption claim.

Canonical `manifest.json` has exactly `backupSchemaVersion`, `consumedEvaluationRootIDs`, `declaredPayloadByteCount`, `entries`, `exportedAt`, `packs`, `source`. Entries cover every nonmanifest member once as `{byteCount,mimeType,path,sha256}` sorted by path; packs are `{contentVersion,packID,schemaVersion}`; source is `{appBuild,appVersion,persistentSchemaVersion:1,recordsSchemaVersion:1}`. Canonical `records.json` has exactly `assets`, `evidenceFiles`, `issues`, `packets`, `recordsSchemaVersion`, `reports`, `sites`, `workflowRecords`; arrays sort by ID and use every exact seven-model DTO field/null. Consumed roots equal every `evaluationCounted=true` Packet. Paths are normalized relative nonsymlink NFC paths with no empty/`.`/`..` segment. Backup excludes commerce, diagnostics, journals, staging, temp, OS metadata, and secrets. Pending regenerates after restore; failed stays failed until Retry.

The data root is immutable-generation based: canonical `FieldEvidenceData/current.json`, canonical `retired.json`, and `FieldEvidenceData/generations/<generation-uuid>/model.sqlite`, `.staging/evidence/<id>/{original.jpg,thumbnail.jpg}`, `evidence/<id>/{original.jpg,thumbnail.jpg}`, snapshots, and PDFs. Absence of the entire data root alone is a fresh-install bootstrap; an existing root with a missing/malformed pointer is corruption. Feature code receives the coordinator context and never retains a container. Pointer corruption/missing generation/multiple claimed current generations opens maintenance; no newest-directory guess. Retired noncurrent generations are deleted only on a later cold launch after proving no prior-process container exists.

S2.1 owns one minimal full-screen `StartupMaintenanceView`, not a recovery framework. Closed reasons are `data_pointer_invalid`, `data_generation_missing`, `finalization_inconsistent`, `media_inconsistent`, `restore_inconsistent`, and `erase_inconsistent`. Title is `Local data needs attention`; copy is `The app stopped to avoid changing or losing local records.` It always offers **Retry checks** and **Recovery steps**. Recovery steps say exactly `If Retry cannot recover this device, delete and reinstall the app. This removes all local app data and does not cancel your Apple subscription. A backup stored outside this app can be restored from Welcome after reinstalling.` S6.4 activates **Restore data backup** and S6.6 activates typed **Erase All** only after startup proves a valid current generation and no active Restore/Erase intent; pointer-invalid/generation-missing/active-journal states use the explicit reinstall route. It offers no raw editing, newest-directory guess, automatic deletion, or local-byte preservation claim. Startup order is fixed: continue/validate Erase before pointer checks; continue/validate Restore before opening current; open/validate current; reconcile finalization, deletion, media, then PDF. Any malformed/unknown intent stops here before feature writes.

Restore journal `Application Support/FieldEvidenceRestore/restore.json` has exactly `newGenerationID`, `newGenerationRelativePath`, `oldGenerationID`, `phase`, `restoreID`, `schemaVersion`, and `stagingGenerationRelativePath`; phase is `prepared|generation_installed|pointer_switched|new_generation_validated`. `prepared` means a complete staged generation validated. `generation_installed` means it was atomically renamed under generations while old stayed current. `pointer_switched` means canonical current pointer names new and coordinator/root injection is rebuilding. `new_generation_validated` means new reopened and every ID/file/hash is readable; then old enters `retired.json` and stage/journal clean up. S6.4 activates the same **Restore data backup** importer/coordinator on Welcome and on maintenance only with a proven valid current generation/no active Restore or Erase intent; S6.5 adds it in Settings for replacement restore. It remains separate from Restore Purchases.

Recovery checks phase plus exact pointer/directory presence. At `prepared`, an installed new directory with old pointer is removed as proven uncommitted; otherwise stage/journal are removed and old remains. At `generation_installed`, old pointer+valid new resumes pointer switch; new pointer+valid new advances; invalid new keeps/repoints old and removes only new. At `pointer_switched`, valid new advances; invalid new atomically repoints old before removing new. At `new_generation_validated`, new must be current/valid, old is retired, cleanup completes. Missing required old, pointer naming neither generation, unexpected transition, malformed journal, or unknown phase opens maintenance and deletes nothing. Existing-data restore unions current/restored counted stable roots and materializes current-only roots as valid staged tombstones.

Erase All requires typed `ERASE`, blocks feature mutation, and writes outside every target at `Application Support/FieldEvidenceErase/erase.json`. `EraseIntentV1` has exactly `auxiliaryRoots`, `eraseID`, `generationIDsToDelete`, `newGenerationID`, `oldGenerationID`, `phase`, and `schemaVersion`. Auxiliary roots are exactly `FieldEvidenceRestore/`, `FieldEvidenceOperations/`, `FieldEvidenceCommerce/`, all `FieldEvidenceDiagnostics/`, `Library/Caches/FieldEvidenceApp/`, `tmp/FieldEvidenceApp/`, and the app bundle ID's UserDefaults persistent domain. Generation IDs are the unique sorted validated existing IDs except the frozen new ID. Phase is `empty_generation_prepared|pointer_switched|session_activated|cleanup_complete`.

`empty_generation_prepared` means the frozen new generation exists and validates empty while old remains current. The operation atomically switches `current.json`, rebuilds the coordinator, and reaches `session_activated` only when the new empty container is active. It deletes only frozen noncurrent IDs after old references drain; otherwise cleanup waits for the next cold launch. It then clears retired IDs, frozen auxiliary roots/default domain, recreates exact-zero diagnostics, verifies zero live/tombstoned roots, reaches `cleanup_complete`, and removes the journal/root.

Recovery is a closed phase/pointer/presence matrix. At `empty_generation_prepared`, old pointer + valid empty new resumes the switch and new pointer + valid empty new advances. At `pointer_switched`, old pointer + valid empty new performs the named switch and new pointer + valid empty new activates/rebuilds the session. At `session_activated`, new must be valid/current/empty; a cold launch opens it and completes any remaining subset of only frozen generation/auxiliary cleanup before zero verification. At `cleanup_complete`, new must remain valid/current/empty; any remaining frozen cleanup is completed and reverified before journal removal. A pointer naming neither old nor new, missing/nonempty/invalid new, generation outside the frozen set, malformed intent, or unknown phase opens maintenance and deletes nothing. Erase runs this matrix before normal pointer maintenance; an exactly named phase-lagged pointer resumes. Erase never calls StoreKit sync/cancel/manage and cannot erase StoreKit state or exported Files.

### 7.5 Commerce and access

The excluded commerce cache is canonical `Application Support/FieldEvidenceCommerce/entitlement.json` with exactly `schemaVersion=1`, `productID`, normalized `state`, nullable `expirationAt`, nullable `graceExpirationAt`, nullable `revocationAt`, `verifiedAt`, and monotonic `hasEverVerifiedPaid`; it stores no JWS, receipt, transaction ID, or content. Only verified transaction/status facts change it. Verified purchase is durably processed, including setting ever-paid, before `finish()`.

`EntitlementReducerV1` accepts verified facts for only the monthly product and outputs only `loading`, `entitled(active,until)`, `entitled(grace,until)`, `never_paid`, or `former_paid_inactive(reason=billing_retry|expired|refunded|revoked)`. Revocation/refund is immediately inactive; trial/subscription/auto-renew-off is active through signed expiration; signed grace is active only through grace expiration; retry outside grace/expiry is inactive. Choose the latest verified product transaction by purchase instant then expiration and fail closed on an unresolved tie. Pending/unverified never replaces a still-valid cache. Offline access ends at recorded signed expiration/grace; no second timer exists. Ordinary startup reads current facts; `AppStore.sync()` occurs only after explicit Restore Purchases.

S7.1 installs the monthly product loader, pure reducer, cache, processor, `Transaction.updates`, shared `.storekit` fixture/scheme setting, and tests **without** `SubscriptionStoreView`, purchase button, or paywall route. S7.2 is the first card allowed to expose purchasing. The `.storekit` file is CI/Simulator-only; TestFlight uses App Store Connect Sandbox product data and a Sandbox tester. Apple Billing Grace is fixed at 16 days for paid-to-paid renewals and Family Sharing is off.

One pure `DraftAccessPolicy` consumes normalized access, `liveAssetCount`, live+tombstoned counted-root IDs, requested entry (`create_sign|check|work|recheck`), and an optional repository-validated existing draft. Precedence is: valid existing draft `continue_existing`; entitled `allow`; former-paid inactive `block_paid`; never-paid permits create-sign only with no live Asset and fewer than three roots, and check/work/recheck only with one live Asset and fewer than three roots. `loading` preserves a still-valid verified cache; known prior-paid with no valid cache returns `wait_for_store`; no cache plus `hasEverVerifiedPaid=false` applies never-paid evaluation so a fresh installation can complete its first report offline. The repository must prove a supplied draft exists, matches requested lineage, predates the gate, and is continuation rather than clone. Corrections/read/preview/share/Files/backup/whole-sign delete/Erase bypass policy. First-sign onboarding has no automatic paywall; purchase appears only after an explicit action that this policy blocks.

### 7.6 Fixed diagnostics and export

`Application Support/FieldEvidenceDiagnostics/counters.json` is exactly the build-plan `DiagnosticsV1` object: six nonnegative saturating Int64 scalars (`first_sign_created`, `onboarding_completed`, `paywall_presented`, `recheck_completed`, `report_saved`, `report_share_sheet_presented`), closed `purchase_result={cancelled,failed,pending,unverified,verified}`, and `schemaVersion:1`; no other key or applied-ID collection is permitted. Unknown/malformed schema resets only this file to the exact zero object and records a privacy-safe OSLog fault.

These counters are non-authoritative, best-effort lower-bound diagnostics. The separately atomically replaced JSON can undercount after a crash or write failure; it never grants access, proves payment, rolls back domain/entitlement success, retries from domain history, or claims cross-store exact-once behavior. There is no applied-ID store. `first_sign_created` increments on the installation's first committed sign. `onboarding_completed` increments only after the first newly created report's Value receipt is actually presented. `report_saved` is attempted after finalization returns `created` for a new evaluation-counted check/recheck root, including CNV; it excludes work, correction, replay, and PDF retry. Every created recheck attempts both `report_saved` and `recheck_completed`. Share increments only after the sheet is presented. Paywall increments once per distinct modal token. Purchase histogram increments once for an explicit user-initiated purchase result only; product loading, renewals/updates, Restore, and Manage never increment it.

`DiagnosticExportV1` canonical JSON has exactly `app={build,version}`, `counters=<exact object>`, `device={model,osVersion}`, `diagnosticSchemaVersion=1`, `generatedAt`, and nullable `metricKit={crashCount,hangCount,launchTimeMilliseconds,peakMemoryBytes}`. Launch-time histogram, when present, is exactly `{under500,from500Through999,from1000Through1999,from2000Up}`. Raw MetricKit/OSLog, paths/hashes/content, labels/notes/addresses, StoreKit product/transaction/status, and credentials are forbidden. The user previews it and may continue without attachment. If no mail account/composer is available, Feedback offers **Copy support address** and **Save diagnostics to Files**; it never silently fails, opens an uneditable `mailto:` attachment path, or sends through a provider.

## 8. Ordered program index

| # | Card | Terminal result | Tier | Next |
|---:|---|---|---|---|
| 1 | S0.1 | Project, scripts, unsigned CI baseline | P12 | S1.1 |
| 2 | S1.1 | Shell, tokens, exact pack | P12 | S2.1 |
| 3 | S2.1 | Site/Asset, store generation, diagnostics | N8 | S2.2 |
| 4 | S2.2 | First site/sign onboarding | P12 | S3.1 |
| 5 | S3.1 | Frozen schema, preflight, one draft | P12 | S3.2 |
| 6 | S3.2 | Imported media runner | P12 | S3.3 |
| 7 | S3.3 | Recoverable finalization/snapshot | F25 | S3.4 |
| 8 | S3.4 | Resume/idempotency/recovery | P12 | S3.5 |
| 9 | S3.5 | Storage/write integrity | P12 | S3.6 |
| 10 | S3.6 | Camera permission/recovery | P12 | S3.7 |
| 11 | S3.7 | Post-draft Could-not-verify | P12 | S4.1 |
| 12 | S4.1 | Byte-deterministic PDF renderer | N8 | S4.2 |
| 13 | S4.2 | PDF failure/retry/relaunch | P12 | S4.3 |
| 14 | S4.3 | Receipt/detail/Share/Files | F25 | S4.4 |
| 15 | S4.4 | Index/history/current/comparison | P12 | S4.5 |
| 16 | S4.5 | Clerical correction/replacement | P12 | S5.1 |
| 17 | S5.1 | Work record, no resolution | P12 | S5.2 |
| 18 | S5.2 | Resolved/still-visible recheck | P12 | S5.3 |
| 19 | S5.3 | Different-issue atomic recheck | P12 | S5.4 |
| 20 | S5.4 | Recheck Could-not-verify | P12 | S6.1 |
| 21 | S6.1 | Whole-sign lineage deletion/tombstones | P12 | S6.2 |
| 22 | S6.2 | UTI + deterministic backup export | P12 | S6.3 |
| 23 | S6.3 | Closed import/package validation | P12 | S6.4 |
| 24 | S6.4 | Empty atomic restore/recovery | F25 | S6.5 |
| 25 | S6.5 | Existing-data replacement/union | F25 | S6.6 |
| 26 | S6.6 | Resumable Erase All | P12 | S7.1 |
| 27 | S7.1 | Reducer/processor core, no purchase UI | N8 | S7.2 |
| 28 | S7.2 | Purchasable paywall/state truth | P12 | S7.3 |
| 29 | S7.3 | Restore/manage/status/offline | F25 | S7.4 |
| 30 | S7.4 | Shared access policy/multi-sign entry | F25 | S7.5 |
| 31 | S7.5 | Lapse/data-right/Erase integration | F25 | S8.1 |
| 32 | S8.1 | Test-only second-pack proof | N8 | S8.2 |
| 33 | S8.2 | Golden-flow accessibility CI | F25 | S8.3 |
| 34 | S8.3 | Private diagnostics/export | P12 | S8.4 |
| 35 | S8.4 | Feedback and attachment consent | P12 | S9.1 |
| 36 | S9.1 | Unsigned RC and inactive release workflow | F25 | S10.1 |
| 37 | S10.1 | Brand activation, inventory, and S9 baselines | F25 | S10.2 |
| 38 | S10.2 | Brand assets, semantic tokens, and components | P12 | S10.3 |
| 39 | S10.3 | Full released-state visual migration | F25 | S10.4 |
| 40 | S10.4 | Automated appearance/accessibility/localization lab | F25 | S10.5 |
| 41 | S10.5 | Owner-bridged physical experience evidence | N8 | S10.6 |
| 42 | S10.6 | Branded release/store/privacy/legal evidence lock | F25 | owner S9.2 |
| owner | S9.2 | Owner-only upload and physical iPhone | owner | S9.3 |
| owner | S9.3 | App Store Connect submission | owner | complete |

## 9. Detailed coding cards

Every card inherits Sections 1–7. `HANDOFF.md` and `Scripts/ci-selection.json` are the only standing support-file exceptions. CURRENT_TASK may explicitly disable either exception during authority-only boundary recovery; the S0 `R` recovery disables both. The selector is updated to the selected card's exact frozen object and is excluded from the file cap; it grants no product scope. Default envelope is 10 production and 5 test/support files; a card's explicit envelope overrides it.

### S0.1 — Repository and unsigned CI baseline

- Anchors/start: plan §§11, 16, 18; owner bootstrap workflow exists on default branch, but no Xcode project/scripts.
- Outcome: checked-in project, shared scheme, synchronized groups, launch-only app, unit/UI targets, four bounded scripts, validated selector file, and fail-closed CI evidence.
- Allowed/forbidden: project, minimal App entry/assets/test roots, `build-smoke.sh`, `test-smoke.sh`, `ui-smoke.sh`, `run-with-timeout.sh`, and selector JSON; no tabs, domain, persistence, pack, camera, report, commerce, or signing. Exact envelope override: five production/project paths and six test/support paths; selector and HANDOFF remain standing exceptions.
- Exact delta: create iOS 18.0 targets/settings and unsigned Simulator route with app bundle ID `com.palatis3.fieldrecord`, unit-test bundle ID `com.palatis3.fieldrecord.tests`, and UI-test bundle ID `com.palatis3.fieldrecord.uitests`; no schema.
- GOLDEN: pinned CI builds, installs, launches one neutral screen, and remains responsive.
- ALT-1: none; unavailable pinned runner/Xcode/runtime stays in the current-card wait/fresh-runner recovery loop and is never silently substituted.
- Selectors/budget: `S0LaunchTests`, `S0LaunchUITests`; P12 exact tier.
- Historical product recovery: failed runs `31562160165` at `I` and `31562792005` at `I2` led to accepted `I3=ac310dd37700d65165200f742aaec1d48d0a34d6` and exact-head run `31566371521`; preserve those project/app/test bytes as S0.1 product implementation evidence.
- Hosted-CI boundary recovery: preserve HANDOFF-only `C`, authority head `R`, K1/K2, and every failed run as history. K3 `e569951909c2ee8aff4253bae0d442550c229a16` passed phase run `31590956549`; its exact-main run `31591804256` failed only the historical 300-second readiness watchdog. Apply lifecycle Steps 4–9 with direct-child K4 installing persistent recovery and the Section 6 values. This is CI verification/integration support, not another S0.1 product outcome; protected product/project/test bytes and historical HANDOFF remain unchanged.
- Terminal/next: green implementation-head evidence and phase-end fast-forward/exact-main CI; next S1.1.

### S1.1 — Shell, Worklight Precision, and exact pack

- Anchors/start: plan §§5, 8, 9 and `IlluminatedSignPack@1`; launch-only app.
- Outcome: Signs/Reports tabs, Settings gear, semantic tokens/components, isolated sample, strict bundled pack loader.
- Allowed/forbidden: `DesignSystem/**`, `Domain/Packs/**`, `Features/{Shell,Sample}/**`, pack/assets, exact App wiring/tests; no SwiftData, runner, generic engine, or remote pack.
- Exact envelope override: up to 27 production paths and 5 test/support paths so the complete Worklight palette can be implemented literally as named asset-catalog Color Sets with Light, Dark, and increased-contrast variants while the shell, strict pack loader, bundled pack, and focused tests remain separately attributable. No other S1.1 production path is authorized by this override.
- Exact delta: no project/schema delta; pack rejects unknown key/version and contains only closed sign nouns/instructions, evidence purpose key/display/instruction, issue labels, CNV reasons, acknowledgement/disclaimer copy, and frozen stage/outcome displays; it defines no PDF layout/order.
- GOLDEN: exact nouns/prompts/issue/CNV/evidence registries render; shell survives largest text and Light/Dark.
- ALT-1: invalid pack shows one local unavailable state and guesses nothing.
- Selectors/budget: `S1PackTokenTests`, `S1ShellUITests`; P12.
- Terminal/next: fixture shell only; phase-end fast-forward/exact-main CI; next S2.1.

### S2.1 — Persistence roots, generation seam, and diagnostics

- Anchors/start: plan §§9, 10, 14; fixture shell.
- Outcome: only exact Site/Asset models, immutable-generation roots/pointers, `StoreSessionCoordinator`, exact `DiagnosticsV1`, fixed startup ordering, and minimal `StartupMaintenanceView` initialized.
- Allowed/forbidden: model file; persistence coordinator/factory; diagnostic store; App injection; minimal maintenance reason/router/view; unit tests; no sign UI, workflow models, evaluation ledger, repository abstraction, raw-file editor, or generic recovery framework.
- Exact delta: schema adds only Site/Asset; create canonical `current.json`/`retired.json`, first generation, diagnostics root/exact counters, and closed maintenance reasons/title/copy/Retry/Recovery-steps actions from Section 7.4.
- GOLDEN: persist/release/reopen fixture Site/Asset through the named current generation; pointer and counters reload identically; startup executes Erase→Restore→current-open→operation reconciliation order.
- ALT-1: parameterized malformed pointer/reason opens the minimal write-blocking maintenance screen with the exact reinstall/data-loss/subscription/backup fallback; corrupt diagnostics alone reset only diagnostics with private OSLog and leave domain/pointers untouched.
- Selectors/budget: `S2PersistenceLedgerTests`; UI selector empty; N8.
- Terminal/next: no sign creation UI; next S2.2.

### S2.2 — Add and reopen the first site/sign

- Anchors/start: onboarding steps 1–2 and free-sign slot; empty store.
- Outcome: Welcome/View sample/Add first sign, required site/sign labels, optional address and nullable zone before draft, sign detail, relaunch reopen; Welcome exposes stable route anchors later activated independently by S6.4 Restore data backup and S7.3 Restore Purchases.
- Allowed/forbidden: `Features/Signs/**`, shell/App calls, existing stores, tests; no second-sign control, map/geocoder, or draft.
- Exact delta: no schema/project delta; first Asset commit attempts only installation-first `first_sign_created`; free-sign authority is live-Asset count plus counted Packet roots, not a second ledger.
- GOLDEN: save first sign, relaunch, reopen exact labels and optional address/zone; Start Check is explicitly next-task unavailable.
- ALT-1: invalid labels/zone focus one accessible validation state and write nothing.
- Selectors/budget: `S2SignSetupTests`, `S2SignSetupUITests`; P12.
- Terminal/next: phase-end fast-forward/exact-main CI; next S3.1.

### S3.1 — Frozen workflow schema, preflight, and one active draft

- Anchors/start: plan §§6, 9 and exact preflight; one saved sign.
- Outcome: add remaining five models, exact DTO types/Issue parent chain, two acknowledgements, stage-aware sole-draft `beginOrResumeDraft(assetID:requestedStage:issueID:)`, pre-begin Cancel, and confirmed IANA zone before draft commit.
- Allowed/forbidden: workflow/snapshot models, time rule, preflight/runner coordinator, sign-detail integration, tests; no capture/finalization.
- Exact delta: schema adds WorkflowRecord/EvidenceFile/Issue/Packet/Report exactly, then freezes; no Observation model.
- GOLDEN: Begin persists one draft and frozen instant/zone/offset/local values/copy; every requested route first returns the Asset's existing draft, and only no-draft state validates stage/Issue lineage to create.
- ALT-1: Cancel before Begin writes nothing and says `No check was started.`
- Selectors/budget: `S3_1DraftSchemaTests`, `S3_1PreflightUITests`; P12.
- Terminal/next: capture/outcome unavailable; next S3.2.

### S3.2 — Imported-fixture media pipeline and runner

- Anchors/start: plan capture/media/storage; committed draft.
- Outcome: normalize/hash/atomic original+thumbnail bundle acceptance for wide then close, Retake/Use Photo, deterministic imported fixtures.
- Allowed/forbidden: media normalizer/store/preflight, capture step/coordinator, photo fixtures/tests; no camera permission or durable non-JPEG.
- Exact delta: none; verify `.staging/evidence/<id>/{original.jpg,thumbnail.jpg}`, atomically rename to `evidence/<id>/`, then commit both paths/counts/hashes and advance.
- GOLDEN: wide/close imports yield exact canonical original+thumbnail MIME/path/count/hash and committed progress without forbidden metadata.
- ALT-1: Retake removes only unaccepted staging bytes and preserves accepted evidence.
- Selectors/budget: `S3_2MediaPipelineTests`, `S3_2ImportedCaptureUITests`; P12.
- Terminal/next: outcome unavailable; next S3.3.

### S3.3 — Outcome, review, recoverable finalization, and snapshot

- Anchors/start: plan §§6, 9–10 and final-choice table; draft with wide/close.
- Outcome: Outcome/Review, one mutation journal, completed record, optional Issue, Packet/root, canonical snapshot, pending Report, shared `Features/CheckRunner/ValueReceiptView.swift` shell.
- Allowed/forbidden: finalization rule/service/journal, outcome/review/value receipt/coordinator, snapshot encoder, tests; no PDF/share or second receipt type.
- Exact delta: no schema/project delta; exact Section 7.2 journal/render-complete snapshot; attempt `report_saved` after a created report, and attempt installation-first `onboarding_completed` only when its Value receipt is actually presented, both as non-authoritative diagnostics.
- GOLDEN: No visible issue creates exactly one completed root/Report, exact effective-source/stage/display/original+thumbnail snapshot DTO, durable snapshot before row, pending PDF, and one presented receipt.
- ALT-1: Visible issue requires one closed label/display and creates exactly one linked Issue.
- Selectors/budget: `S3_3FinalizationTests`, `S3_3GoldenCheckUITests`; F25.
- Terminal/next: View Report/Share unavailable; next S3.4.

### S3.4 — Resume, mutation idempotency, and finalization recovery

- Anchors/start: lifecycle/storage rules; drafts/journals at each committed checkpoint.
- Outcome: relaunch resumes exact step; begin/evidence/finalization replay returns prior authority; journal recovery covers the full phase-and-stage/final-presence matrix and crash-after-save-before-phase-write.
- Allowed/forbidden: existing runner/media/finalization/coordinator plus exact tests; no event log or generic mutation bus.
- Exact delta: none.
- GOLDEN: force-quit after wide resumes at close with the same file; double Save returns identical record/packet/report/root.
- ALT-1: parameterized `prepared|snapshot_promoted|database_committed` presence cases recover to resumable draft or one complete report; any mismatch reaches maintenance, never an orphan/duplicate/guess.
- Selectors/budget: `S3_4ResumeRecoveryTests`, `S3_4ResumeUITests`; P12.
- Terminal/next: next S3.5.

### S3.5 — Low-storage and write-failure integrity

- Anchors/start: plan storage rules/release blockers; committed draft.
- Outcome: bounded injection seams for preflight, move, snapshot, and database failures; prior commits remain readable.
- Allowed/forbidden: existing services, `TestFixtures/Failures/**`, tests; no fuzz/endurance/global fault framework.
- Exact delta: none.
- GOLDEN: insufficient capacity blocks before new row/file and leaves draft retryable.
- ALT-1: parameterized write-failure family rolls back only the active mutation and later retry succeeds.
- Selectors/budget: `S3_5FailureIntegrityTests`, `S3_5FailureRecoveryUITests`; P12.
- Terminal/next: next S3.6.

### S3.6 — Camera permission and denial recovery

- Anchors/start: onboarding capture and permission gate; imported pipeline is green.
- Outcome: user-requested camera adapter; PhotosPicker/Open Settings/safe incomplete route; no launch prompt.
- Allowed/forbidden: CameraAdapter, permission/capture views, exact project usage key, tests; no broad library, location, microphone, or contacts permission.
- Exact delta: add only `NSCameraUsageDescription = Use the camera to add sign photos to reports stored on this iPhone.`
- GOLDEN: authorized fixture adapter returns wide/close through the existing normalizer.
- ALT-1: denied-permission family offers PhotosPicker or Settings/resumable exit without stranding the draft.
- Selectors/budget: `S3_6CameraRecoveryTests`, `S3_6CameraRecoveryUITests`; P12.
- Terminal/next: CI proves state handling, not physical quality; next S3.7.

### S3.7 — Post-draft Could-not-verify

- Anchors/start: exact CNV registry/finalization effects; draft exists.
- Outcome: closed reason/display/version plus optional note completes honest incomplete root while preserving accepted evidence.
- Allowed/forbidden: existing outcome/review/finalization/runner and tests; no pass, Issue, resolution, or billing event.
- Exact delta: none.
- GOLDEN: one wide + `required_view_obstructed` creates one incomplete snapshot/Report/root.
- ALT-1: zero-photo `capture_unavailable` creates the same honest incomplete shape.
- Selectors/budget: `S3_7CouldNotVerifyTests`, `S3_7CouldNotVerifyUITests`; P12.
- Terminal/next: phase-end fast-forward/exact-main CI; next S4.1.

### S4.1 — Byte-deterministic snapshot-to-PDF renderer

- Anchors/start: plan report truth/snapshot order; pending Report with durable snapshot.
- Outcome: exact two-pass `WorklightPDFRendererV1` and render service produce ready PDF only from the validated snapshot/effective-source current evidence.
- Allowed/forbidden: reporting renderer/service, PDF fixtures/unit tests; no history UI/share/template engine.
- Exact delta: none; implement Section 7.3 Letter rectangles, built-in fonts/line heights/spacing/pagination, current-original/history-thumbnail bounds, footer, metadata, and order exactly; no pack/database lookup.
- GOLDEN: same fixture rendered twice in clean roots yields byte-identical PDF/hash and exact text/image geometry; missing CNV current evidence shows the frozen missing label and never substitutes history.
- ALT-1: changed device zone/DST leaves historical snapshot content/bytes unchanged.
- Selectors/budget: `S4_1DeterministicRendererTests`; UI selector empty; N8.
- Terminal/next: next S4.2.

### S4.2 — PDF failure, relaunch reconciliation, and Retry

- Anchors/start: Report state machine/release blockers; pending/failed fixtures.
- Outcome: failures preserve source/snapshot; launch reconciles row/bytes; explicit Retry is bounded.
- Allowed/forbidden: report service/reconciler and one failure view, tests; no automatic retry loop or replacement Report.
- Exact delta: none.
- GOLDEN: injected render failure becomes failed; Retry after fault removal becomes ready from unchanged snapshot.
- ALT-1: interrupted promotion/relaunch reconciles to ready only with matching bytes/hash, otherwise failed/retryable.
- Selectors/budget: `S4_2PDFRecoveryTests`, `S4_2PDFRetryUITests`; P12.
- Terminal/next: next S4.3.

### S4.3 — Value receipt, detail, preview, Share, and Files

- Anchors/start: onboarding receipt/report truth; ready Report.
- Outcome: activate the single CheckRunner ValueReceipt; report detail/preview, system Share, user Files destination, Done to sign.
- Allowed/forbidden: existing CheckRunner receipt plus report detail/preview/export coordinator/tests; no second `ValueReceiptView`, hosted link, email provider, or delivery receipt.
- Exact delta: none; share counter increments only when sheet is presented.
- GOLDEN: receipt→preview→Share→Files exports identical cached bytes and relaunch reopens same hash.
- ALT-1: user cancels system presentation; no sent/opened/delivered fact or data mutation.
- Selectors/budget: `S4_3ReportDeliveryTests`, `S4_3ValueReceiptUITests`; F25.
- Terminal/next: next S4.4.

### S4.4 — Reports index, history, current revision, and comparison

- Anchors/start: plan navigation/comparison; multiple sites/signs/packet revisions.
- Outcome: newest-first Reports index, site/sign filters, sign history, current revision per root, immediately previous distinct-packet comparison.
- Allowed/forbidden: index/query/history/comparison rule/view and shell/sign integration/tests; no search, AI, image scoring, or correction-as-visit.
- Exact delta: none.
- GOLDEN: filtered history selects current revisions and shows exact Then/Now evidence/dates for two unambiguous visits.
- ALT-1: ambiguous ordering or missing required evidence omits comparison and keeps chronological history accessible.
- Selectors/budget: `S4_4HistoryComparisonTests`, `S4_4ReportsUITests`; P12.
- Terminal/next: next S4.5.

### S4.5 — Clerical correction and forward replacement

- Anchors/start: correction/replacement invariants; current ready Report.
- Outcome: note-only correction creates completed revision, canonical snapshot copied from the immediately prior current Report with only the five allowed changes, pending→ready replacement; all prior bytes remain readable.
- Allowed/forbidden: correction rule/view and shared finalization/report services/tests; cannot alter evidence/time/outcome/issue/pack or add schema fields.
- Exact delta: none; correction never increments `report_saved` or consumes an evaluation root.
- GOLDEN: one correction points to original evidence, replaces prior Report forward-only, preserves frozen labels/issue cutoff/history/evidence, and opens both PDFs.
- ALT-1: second correction revises the prior correction but still points evidence directly to the original without duplication.
- Selectors/budget: `S4_5CorrectionTests`, `S4_5CorrectionUITests`; P12.
- Terminal/next: phase-end fast-forward/exact-main CI; next S5.1.

### S5.1 — Record work without resolution

- Anchors/start: plan work/recheck; open Issue.
- Outcome: required local date/short description, optional note, zero/one work photo; parent is the Issue chain's latest completed substantive record; Issue becomes recheck_due; no Packet/Report/root.
- Allowed/forbidden: Issue detail/work view, WorkRule, existing media/persistence, tests; work never resolves or consumes evaluation.
- Exact delta: none; exact work fields from frozen schema.
- GOLDEN: save work with one `work_context`, reopen description/date/photo, Issue remains unresolved.
- ALT-1: validation family writes nothing for missing description/date or invalid evidence purpose/count.
- Selectors/budget: `S5_1RecordWorkTests`, `S5_1RecordWorkUITests`; P12.
- Terminal/next: next S5.2.

### S5.2 — Resolved or still-visible recheck

- Anchors/start: recheck evidence rule; recheck_due Issue.
- Outcome: new time context + new wide/close, parent to the recheck_due Issue's latest substantive record, explicit original-Issue link, Packet/Report/root; attempt recheck/report lower-bound diagnostics after a created result.
- Allowed/forbidden: recheck entry/rule and exact runner/finalization extension/tests; prior photos cannot satisfy evidence.
- Exact delta: none.
- GOLDEN: Resolved atomically sets original `resolvedByRecordID` and creates one Report/root.
- ALT-1: Issue still visible returns the same Issue to open and creates no new Issue UUID.
- Selectors/budget: `S5_2RecheckOutcomeTests`, `S5_2RecheckUITests`; P12.
- Terminal/next: next S5.3.

### S5.3 — Original resolved, different visible issue

- Anchors/start: atomic transition rule; recheck_due original with new evidence.
- Outcome: resolve original and open one new Issue UUID with closed label in the same recoverable finalization; attempt both lower-bound diagnostics only after a created result.
- Allowed/forbidden: existing recheck/finalization/views/tests; no implicit original state or multiple issues.
- Exact delta: none.
- GOLDEN: old resolved/new open/Packet/Report/root commit together and only then attempt diagnostics.
- ALT-1: injected transaction failure rolls back the complete domain transition and makes no diagnostic attempt.
- Selectors/budget: `S5_3DifferentIssueTests`, `S5_3DifferentIssueUITests`; P12.
- Terminal/next: next S5.4.

### S5.4 — Recheck Could-not-verify

- Anchors/start: recheck CNV invariant; recheck_due Issue.
- Outcome: zero/partial new evidence creates incomplete Report/root, leaves original recheck_due, and then attempts both lower-bound diagnostics.
- Allowed/forbidden: existing CNV/recheck/finalization/tests; never resolve/open/pass/refund.
- Exact delta: none.
- GOLDEN: partial evidence + `conditions_changed` preserves original Issue authority.
- ALT-1: zero evidence + `unsafe_to_continue` has the same Issue effect.
- Selectors/budget: `S5_4RecheckCNVTests`, `S5_4RecheckCNVUITests`; P12.
- Terminal/next: phase-end fast-forward/exact-main CI; next S6.1.

### S6.1 — Whole-sign lineage deletion and tombstones

- Anchors/start: free-evaluation/deletion invariant; one complete Asset lineage with counted and uncounted Packets.
- Outcome: exact truthful confirmation journals and removes the referentially closed visible graph, retains content-free counted-root tombstones, and frees only the concurrent live-sign slot.
- Allowed/forbidden: deletion intent/rule/service/view/tests; no Packet/report/issue fragment delete, undo, cloud trash, or entitlement change.
- Exact delta: add only exact `DeletionIntentV1` and Section 7.4 recovery; no schema change.
- GOLDEN: the exact Section 7.4 confirmation removes every visible row/file in its closed lineage, removes Site only if empty, retains one anonymous valid tombstone per counted root, and leaves no dangling ID/content.
- ALT-1: interruption before/after the database commit cancels safely or completes only the intent-owned path cleanup on relaunch.
- Selectors/budget: `S6_1DeletionGraphTests`, `S6_1DeletionUITests`; P12.
- Terminal/next: next S6.2.

### S6.2 — Proprietary UTI and deterministic backup export

- Anchors/start: exact `V4Backup@1`; live data, tombstone, ready Report.
- Outcome: custom package type, confirmed Files export, canonical manifest/records, exact unchanged live-original→`media/` and live-thumbnail→`thumbnails/` mapping, snapshots/ready PDFs, exact warning.
- Allowed/forbidden: backup DTO/export/view, UTI Info setting, fixtures/tests; no ZIP/encryption claim/commerce/diagnostics/temp.
- Exact delta: project adds only exported package UTI/extension; schema none.
- GOLDEN: export a mixed ready/pending/failed fixture; independently recompute exact paths/counts/original+thumbnail hashes/root/slot equality and warning, require only the ready PDF entry, and prove pending/failed snapshots remain present.
- ALT-1: injected destination capacity below the declared-payload-plus-20-percent estimate blocks before any destination package is created and leaves live data unchanged.
- Selectors/budget: `S6_2BackupExportTests`, `S6_2BackupExportUITests`; P12.
- Terminal/next: next S6.3.

### S6.3 — Backup import, staging, and closed validation

- Anchors/start: exact rejection rules; selected package, untouched live store.
- Outcome: copy to stage, validate path/symlink/member/hash/bytes/MIME/canonical original+thumbnail media/schema/pack/template/IDs/relationships/counted-root equality/capacity, show safe summary.
- Allowed/forbidden: importer/validator/summary view/fixtures/tests; no migration, repair, partial import, or live mutation.
- Exact delta: none.
- GOLDEN: exact fixture yields deterministic counts/date/size/pack/root/slot summary.
- ALT-1: one parameterized invalid-package family rejects before live mutation.
- Selectors/budget: `S6_3BackupValidationTests`, `S6_3BackupValidationUITests`; P12.
- Terminal/next: next S6.4.

### S6.4 — Empty-install atomic restore and presence-matrix recovery

- Anchors/start: validated package and valid empty current generation; StoreSession generation seam.
- Outcome: activate **Restore data backup** on Welcome and, only with a proven valid current generation/no active Restore or Erase intent, on `StartupMaintenanceView`; materialize a new immutable generation, confirm, install, atomically switch `current.json`, reopen/validate, retire old, regenerate pending PDFs, and rebuild the UI generation.
- Allowed/forbidden: restore coordinator/exact journal/progress view, Welcome/maintenance route retrofit, coordinator integration/tests; no existing-data union, active-generation rename/delete, newest-directory guess, or conflation with Restore Purchases.
- Exact delta: none; journal has only the seven Section 7.4 keys/phases.
- GOLDEN: eligible routes call the same importer; pointer-invalid/generation-missing maintenance never offers it; restore all IDs/files/hashes; pending rerenders, failed remains failed until Retry; canonical pointer names the validated generation and UI rebuilds.
- ALT-1: parameterized interruption family across `prepared|generation_installed|pointer_switched|new_generation_validated` yields the prior valid generation or fully validated new generation without deleting required old data.
- Selectors/budget: `S6_4AtomicRestoreTests`, `S6_4AtomicRestoreUITests`; F25.
- Terminal/next: next S6.5.

### S6.5 — Replace existing data and monotonic union

- Anchors/start: current data plus validated different backup.
- Outcome: activate Settings **Restore data backup**; current/incoming summary, optional current backup, explicit Replace, monotonic counted-root union, current-only tombstones, exact immutable-generation pointer switch.
- Allowed/forbidden: evaluation union and existing restore views/coordinator/tests; no entitlement import or evaluation decrement.
- Exact delta: none.
- GOLDEN: current counted root A + restored live root B yields live B, valid tombstone A, and counted roots `{A,B}` without importing entitlement or diagnostics.
- ALT-1: cancel before confirmation leaves no stage/journal and changes no live byte.
- Selectors/budget: `S6_5ReplacementUnionTests`, `S6_5ReplacementUITests`; F25.
- Terminal/next: next S6.6.

### S6.6 — Resumable Erase All

- Anchors/start: named app roots/caches/counters and erase marker; data-rights smoke.
- Outcome: typed confirmation, exact four-phase generation-switch journal, clean validated generation/zero diagnostics, safe retired-generation cleanup, generation rebuild, separate-subscription copy, and maintenance Erase activation only with the same proven-valid-current/no-active-journal precondition.
- Allowed/forbidden: Erase service/exact marker/view/Settings+maintenance retrofit/tests; no active-container deletion, StoreKit cancel/sync, OS-container erase, or broadened target discovery.
- Exact delta: none.
- GOLDEN: interrupt before/after each pointer/phase write across `empty_generation_prepared|pointer_switched|session_activated|cleanup_complete`, relaunch before pointer maintenance, finish the exact presence matrix, verify zero live/tombstoned roots/counters, fresh active generation, only frozen old IDs removed after references drain, no marker, and no StoreKit sync/cancel call.
- ALT-1: Cancel before marker changes no byte/row/counter.
- Selectors/budget: `S6_6EraseRecoveryTests`, `S6_6EraseAllUITests`; P12.
- Terminal/next: phase-end fast-forward/exact-main CI; next S7.1 uses the already frozen repository-local fixture facts: product ID `com.palatis3.fieldrecord.sub.solo.monthly.v1`, 14-day introductory-offer fixture, 16-day paid-to-paid grace, and Family Sharing off. These are not a new owner-input gate. No App Store SKU exists unless the commitment gate passed.

### S7.1 — StoreKit reducer and durable processor core, no purchase UI

- Anchors/start: plan purchase-state table; data phase complete; monthly product ID `com.palatis3.fieldrecord.sub.solo.monthly.v1` is frozen, but no StoreKit fixture or purchase UI exists yet.
- Outcome: product loader, exact entitlement facts/store, pure reducer, transaction processor/observer, offline cache interpretation; no purchasable view.
- Allowed/forbidden: StoreKit infrastructure, fixture/scheme setting, unit tests; `SubscriptionStoreView`, purchase button, paywall route, sync, and unlock UI are forbidden.
- Exact delta: add one shared CI/Simulator-only `TestFixtures/StoreKit/FieldEvidence.storekit` configuration for `com.palatis3.fieldrecord.sub.solo.monthly.v1` plus its scheme setting; no schema or App Store Connect mutation.
- GOLDEN: parameterized verified-state table reduces active/trial/grace/auto-renew-off/billing/expired/refund/revocation/offline facts and persists-before-finish.
- ALT-1: unverified/pending/cancelled/failed inputs never mutate paid facts or finish an unverified transaction.
- Selectors/budget: `S7_1CommerceCoreTests`; UI selector empty; N8.
- Terminal/next: processor is active at app startup; next S7.2.

### S7.2 — Purchasable paywall and purchase-state truth

- Anchors/start: S7.1 processor active; exact monthly product and reserved nonresolving test links `https://example.invalid/terms`, `https://example.invalid/privacy`, and `https://example.invalid/support`; production links remain absent and fail closed.
- Outcome: only now add `SubscriptionStoreView(productIDs:)`; loading/unavailable, eligible/ineligible, purchasing, cancel, pending, verified, unverified, failed; localized disclosure and close-to-history.
- Allowed/forbidden: paywall/catalog links/Settings entry and tests; no annual, hardcoded price, web checkout, external link, or remote paywall.
- Exact delta: no schema; Terms/Privacy/Support use injected test values and fail closed when production config is missing; `paywall_presented` increments once per distinct modal token.
- GOLDEN: eligible purchase shows exact trial/renewal/no-sync disclosures; verified result flows through the preinstalled processor, unlocks only after durable write, and records one verified bucket. The same table-driven test contract verifies cancelled, pending, unverified, and failed results keep existing data visible, do not unlock, release the purchasing/double-tap lock, show their exact recovery copy, and increment only the matching diagnostic bucket.
- ALT-1: unavailable-product/link family shows honest retry/close and no price/trial guess.
- Selectors/budget: `S7_2PaywallPurchaseTests`, `S7_2PaywallUITests`; P12.
- Terminal/next: next S7.3.

### S7.3 — Restore, manage, lifecycle status, and offline refresh

- Anchors/start: commerce core/paywall; all signed status fixtures.
- Outcome: activate separate **Restore Purchases** actions on Welcome and Settings; system Manage Subscription, renewal/grace/billing/expiry/refund/revocation UI, startup/offline refresh, transaction updates.
- Allowed/forbidden: Welcome/Settings subscription route retrofit, status/refresh and existing StoreKit client/tests; no automatic `AppStore.sync()`, Restore data backup conflation, or server receipt system.
- Exact delta: none; fixed 16-day paid-to-paid grace and Family Sharing off are test/owner confirmations.
- GOLDEN: explicit restore processes verified current entitlement, persists access, and status matrix preserves data visibility with exact `Active until` copy.
- ALT-1: offline/lapsed family honors cached signed facts only through expiration and never invents grace/unlock.
- Selectors/budget: `S7_3LifecycleRestoreTests`, `S7_3LifecycleUITests`; F25.
- Terminal/next: next S7.4.

### S7.4 — Shared DraftAccessPolicy and paid multi-sign entry

- Anchors/start: all commerce states exist; live-Asset and live/tombstoned counted-root accounting is green.
- Outcome: one pure repository-backed policy at create-sign/check/work/recheck, including the fresh-offline never-paid loading branch; activate Add sign using S2 form with existing-site choice or New site; validated existing drafts finish.
- Allowed/forbidden: DraftAccessPolicy, exact Signs/CheckRunner/Issues entry coordinators, paywall route/tests; no fingerprint/backend/route-specific policies.
- Exact delta: none.
- GOLDEN: never-paid one live sign plus three counted roots blocks an explicit new-value action before any row/file and opens the same closable paywall; first-sign onboarding never auto-presents it.
- ALT-1: fresh loading with no cache/ever-paid permits the never-paid first offline report; known prior-paid without valid cache waits. Deleting the only sign below three roots permits one replacement, while three roots do not; active entitlement permits multiple Assets.
- Selectors/budget: `S7_4DraftAccessPolicyTests`, `S7_4AccessGateUITests`; F25.
- Terminal/next: next S7.5.

### S7.5 — Lapse/data rights and Erase-subscription independence

- Anchors/start: domain/data-right/commerce integration complete.
- Outcome: inactive states block only new value authority; all existing-data rights and existing draft completion remain; Erase does not cancel billing and active access rediscovers.
- Allowed/forbidden: exact integration coordinators/views/services/tests; no new subsystem, cancellation, account deletion, or remote erase.
- Exact delta: none.
- GOLDEN: former-paid lapse reads/previews/shares/Files-exports/backs up/retries PDF/corrects/deletes and completes existing draft, while new sign/draft opens paywall.
- ALT-1: active subscriber Erase makes no cancel/sync call; clean launch rediscovers active verified entitlement with empty local evaluation.
- Selectors/budget: `S7_5DataRightsIntegrationTests`, `S7_5LapseRightsUITests`; F25.
- Terminal/next: phase-end fast-forward/exact-main CI; next S8.1.

### S8.1 — Nonshipping exterior-light zero-fork proof

- Anchors/start: reusable pack seam and smoke 11; full production sign flow.
- Outcome: test-only exterior-light fixture completes check→snapshot→PDF through identical interfaces with zero production branch.
- Allowed/forbidden: one fixture JSON and tests only; zero production files; fixture is never bundled/selectable/public/priced.
- Exact delta: none.
- GOLDEN: exact fixture nouns/purpose/current-and-history stage/outcome display copy freeze into the snapshot and flow through the renderer with no render-time pack/registry lookup; production diff is zero.
- ALT-1: if the proof identifies a production reusable-seam defect, keep S8.1 active and create one direct-child correction limited to the exact earlier-card-owned production paths that introduced it; the unchanged S8.1 selector must exercise the corrected seam, then rerun S8.1. The correction preserves public product scope and may not add a production second-pack branch.
- Selectors/budget: `S8_1SecondPackZeroForkTests`; UI selector empty; N8.
- Terminal/next: next S8.2.

### S8.2 — Full golden-flow accessibility CI

- Anchors/start: incremental semantics green; smoke 12.
- Outcome: one bounded fresh-install class traverses first sign→check→report→issue/work/recheck→Settings/paywall using accessibility IDs and named checkpoints.
- Allowed/forbidden: one unit-test class plus one UI fixture/class in the S8.2 verification commit; no visual redesign/device/locale/orientation matrix. If verification identifies a production defect, keep S8.2 active and create one direct-child correction limited to the exact production paths owned by the prior card that introduced the failed semantic; the unchanged S8.2 selector must exercise the correction, then rerun the unchanged S8.2 proof.
- Exact delta: none.
- GOLDEN: route completes default Light then checkpoints largest-accessibility Dark, labels/traits/order/focus/non-color state/44-point targets.
- ALT-1: one representative validation/permission error receives actionable focus without color-only meaning.
- Selectors/budget: `S8_2GoldenAccessibilityTests`, `S8_2GoldenAccessibilityUITests`; F25.
- Terminal/next: a production defect follows the in-place S8.2 corrective-head loop above and then a fresh S8.2 run; otherwise next S8.3.

### S8.3 — Privacy-safe OSLog, MetricKit, and diagnostic export

- Anchors/start: fixed producers exist; plan §14.
- Outcome: private logging, bounded MetricKit summaries, owner-invoked preview/export with only allowed system context and explicitly non-authoritative best-effort lower-bound diagnostics.
- Allowed/forbidden: diagnostics logger/adapter/export/Settings view/tests; no upload, Sentry/PostHog, raw database/media/report/backup/log stream.
- Exact delta: none.
- GOLDEN: controlled values export canonical allowed keys; hostile customer strings/paths/hashes/transaction IDs are absent; counter failure never gates access/payment or rolls back domain work.
- ALT-1: empty/undercounted counters and absent payload yield a valid minimal export and make no exact-once or authoritative cohort claim.
- Selectors/budget: `S8_3DiagnosticPrivacyTests`, `S8_3DiagnosticExportUITests`; P12.
- Terminal/next: next S8.4.

### S8.4 — Feedback with explicit attachment consent

- Anchors/start: diagnostic preview/export; final support email not supplied until S9.
- Outcome: user-authored mail adapter; controlled test support address; review then Attach or Don't Attach; missing production address fails closed; unavailable mail offers Copy support address and Save diagnostics to Files.
- Allowed/forbidden: feedback/mail adapter, config seam, Settings integration/tests; no provider send, background upload, ticket SDK, hardcoded production email, or customer-content prefill.
- Exact delta: none; S9.1 alone supplies final production support email.
- GOLDEN: user reviews exact sanitized file, chooses Attach, and editable composer receives one attachment.
- ALT-1: Don't Attach opens the same editable feedback with zero attachments; unavailable composer never silently fails or attempts provider/mailto attachment delivery.
- Selectors/budget: `S8_4FeedbackConsentTests`, `S8_4FeedbackUITests`; P12.
- Terminal/next: phase-end fast-forward/exact-main CI; next S9.1 prehydrates only already frozen metadata and continues every independently derivable release artifact. Unspecified live release values are recorded explicitly and never invented.

### S9.1 — Unsigned release candidate and inactive TestFlight workflow

- Anchors/start: feature-complete exact-main; prehydrate app bundle ID `com.palatis3.fieldrecord`, test bundle IDs, and product ID `com.palatis3.fieldrecord.sub.solo.monthly.v1`. The adopted display/App Store title still requires professional clearance. Live URLs/support email/title clearance/App record/version/build/privacy inputs and six-of-ten production-SKU gate are validated only when authoritative values exist; they are never fabricated.
- Outcome: unsigned RC config/assets, PrivacyInfo, metadata/review checklist, 12-smoke evidence index, a complete inactive owner-only TestFlight workflow, provided-value config, and a machine-readable release-input manifest that records every required external live value as `provided` or `pending`; release-ready status is true only when every required value is provided; no signing/upload.
- Allowed/forbidden: `Release/**`, exact project/resource/version settings, privacy manifest, `.github/workflows/testflight.yml`, bounded scripts/tests; no feature, backend, analytics SDK, secret, signing, upload, or submission.
- Exact delta: release settings only; workflow checks the owner-reviewed exact `main` SHA under the private-solo ref rule, serializes, uses environment secrets/ephemeral keychain, SHA-pinned `actions/*`, Apple-native tools, and no automatic upload retry. S9.1 commits no secret and performs no signing/upload; missing external live values remain explicit preflight findings while all repository-derived RC/privacy/metadata/workflow evidence proceeds.
- GOLDEN: ordinary unsigned CI builds/tests the RC, validates every provided live link/email/metadata/privacy value plus the complete pending/provided manifest and inactive workflow without secrets, runs final golden smoke, and creates the evidence index. A pending external value is explicit non-release-ready evidence, not fabricated data and not a coding failure.
- ALT-1: one release-preflight family fails closed for malformed or inconsistent provided config, an omitted manifest key, privacy inconsistency, wrong or unexpectedly moved `main` ref, or secret-boundary violation. Pending external values keep S9.2 unavailable but do not block completion of the unsigned S9.1 coding artifact.
- Selectors/budget: `S9_1ReleasePreflightTests`, `S9_1FinalRCUITests`; F25.
- Terminal/next: phase-end fast-forward/exact-main CI; next S10.1 on `phase/s10-brand-refresh` from the accepted exact-main unpublished candidate.

### S10.1 — Brand activation, released-state inventory, and corrected S9 baselines

- Anchors/start: owner-approved Brand Handoff V4.1, exact accepted S9 unpublished-candidate base and exact-main run, frozen ZIP/manifest digests, accepted use grant, current/minimum device profiles, release locale, six pseudolanguage profiles, and planned owner-operated physical bridge.
- Outcome: freeze the one-to-one six-stage S10 contract, complete released route/state and common-task inventory, map every state to the approved token catalog, correct the diagnosed prebaseline S9 lineage defects across work admission and atomic finalization/recovery, and capture immutable pre-migration screenshots of that corrected unpublished candidate before any brand/presentation byte changes.
- Allowed/forbidden: exactly the seven canonical inventory/coverage JSON instances, `FieldEvidenceApp/Features/Issues/WorkCoordinator.swift`, `FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift`, `FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift`, `FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift`, `S10_1BrandInventoryTests.swift`, and `S10_1BrandInventoryUITests.swift`; activation/authority bytes are owner-directed correction authority and selector/HANDOFF remain standing exceptions. App mutation is limited to the closed repeated work/recheck lineage grammar diagnosed by hosted runs `31919914831` and `31922598904`, plus the test-only pending-receipt seam diagnosed by hosted run `31925253501`: work admission; matching precommit, replay, and recovery authority; and deterministic deferral of receipt PDF preparation only when the existing `--s4-2-ui-test-render-failure-once` launch argument is present. No other app, project, asset, feature, fixture, release-metadata, or design-token mutation. Explicit envelope override: 11 product/document files and 2 test files because the V4.1 validator requires the seven one-to-one canonical instances, the three earlier-card-owned lineage corrections, one test-only pending-receipt seam, and a UI baseline-capture lane.
- Exact delta: documentation, machine-readable coverage, the diagnosed repeated-lineage corrections, the bounded test-only pending-receipt seam, and baseline evidence only. Inventory uses stable route/state IDs and points to existing source identifiers/fixtures; planned later tokens are `planned`, every visual row is `baseline_frozen`, and candidate/review fields remain blank or `NOT_RUN`/`NOT_REVIEWED`. The corrected candidate—not either defective tap path—is the frozen S9 behavioral baseline. The receipt seam leaves normal launches unchanged and still requires startup recovery to attempt, fail, persist, and explicitly retry the genuine pending PDF.
- GOLDEN: F25 UI proof traverses every frozen baseline-capture scenario on the accepted S9 UI without changing product bytes, uploads exact screenshots, and the package validator proves exact state↔token↔baseline coverage, common-task reachability, accessibility matrix, store-slot plan, and six checkpoints.
- ALT-1: an omitted/duplicate route or state, stale source path, unknown token, missing baseline, mismatched selector/hash, unauthorized package member, or fabricated physical/legal/release fact fails closed without regenerating or accepting a baseline.
- Selectors/budget: `S10_1BrandInventoryTests`, `S10_1BrandInventoryUITests`; F25.
- Terminal/next: record accepted product E, descendant evidence K when screenshot/document evidence must be committed after E, later receipt C only as bookkeeping; next S10.2.

### S10.2 — Brand assets, semantic tokens, and reusable components

- Anchors/start: accepted S10.1 inventory/baselines and the installation map's exact 12 runtime files.
- Outcome: install the exact three AppIcon appearances and two original/template symbol image sets, set the effective AppIcon catalog name, and implement the frozen semantic color/type/spacing/radius/stroke/environment/component roles without migrating released screens.
- Allowed/forbidden: the exact 12 runtime asset destinations; six named brand color-set `Contents.json` files; `DesignTokens.swift`, `WorklightComponents.swift`, `project.pbxproj`; and one unit/one UI test. Explicit envelope override: 21 production files and 2 test files because the package fixes 12 runtime files, six custom color roles, two shared design-system sources, and one project integration path. No feature view migration, copy change, schema/model/service/navigation change, source-reference/research/scorecard bundle member, custom font, decorative glass, or custom familiar-action icon.
- Exact delta: component-system primitives only; existing released screens remain baseline-equivalent until S10.3.
- GOLDEN: asset bytes/catalog metadata/dimensions/rendering intent and effective build setting match the package; components prove Light/Dark/increased-contrast, Dynamic Type, 44-point targets, non-color status, Reduce Motion/Transparency behavior, and restrained original/template mark use.
- ALT-1: a mismatched source hash, extra bundled package member, invalid appearance, raw feature hex, unavailable semantic fallback, or baseline-affecting feature edit fails closed and leaves S10.1 evidence unchanged.
- Selectors/budget: `S10_2BrandComponentTests`, `S10_2BrandComponentUITests`; P12.
- Terminal/next: next S10.3.

### S10.3 — Full released-state visual migration

- Anchors/start: exact S10.1 inventory/baselines plus accepted S10.2 components.
- Outcome: migrate every released app state named by the frozen inventory to the approved AssetRounds identity and shared semantic components while preserving behavior, accessibility identifiers, navigation, persistence, commerce, report/backup bytes, and evidence rendering.
- Allowed/forbidden: the exact 26 released SwiftUI source files enumerated by activation plus one unit and one UI migration test. Explicit envelope override: 26 production files and 2 test files because the frozen inventory covers all released SwiftUI states and partial migration is prohibited. Diagnosed S10.2 recovery may additionally change only `FieldEvidenceApp/DesignSystem/WorklightComponents.swift` to add a content-preserving `AssetRoundsPhotoCapture` composition initializer when the accepted capture/retake-only API cannot preserve the frozen native PhotosPicker, Retake/Use Photo, read-only evidence, actions, and accessibility identifiers; this earlier-card-owned correction is excluded from the 26 migrated-screen cap and may not change existing component initializers or behavior. No coordinator/model/store/service/schema/permission/commerce/backup/report-content behavior change; no untasked copy, route, or data mutation.
- Exact delta: presentation and identity only. Evidence photos remain untinted/aspect-correct, native controls/SF Symbols remain familiar, and one primary action per state is preserved.
- GOLDEN: the full representative fresh-install→check/report→issue/work/recheck→Settings/commerce/data-rights route and every inventory exception state render from the shared brand system in Light and Dark with unchanged semantic outcomes and durable bytes.
- ALT-1: any missing state, clipped/lost action, color-only meaning, changed AX identifier/order, altered report/snapshot/backup output, unexpected navigation/model write, or silent baseline regeneration fails closed.
- Selectors/budget: `S10_3BrandMigrationTests`, `S10_3BrandMigrationUITests`; F25.
- Terminal/next: next S10.4.

### S10.4 — Automated appearance, accessibility, and localization lab

- Anchors/start: accepted branded migration and exact device/locale/pseudolanguage matrix.
- Outcome: execute and lock automated current/minimum platform, Light/Dark, increased contrast, largest accessibility text, Differentiate Without Color, Reduce Motion, Reduce Transparency, VoiceOver/Voice Control semantics, and all six pseudolanguage profiles against every common task/state.
- Allowed/forbidden: the canonical stage/accessibility/token/visual evidence documents plus one unit and one UI lab test; no product/app/project/asset/fixture mutation unless a diagnosed S10.2/S10.3 defect is corrected in place on the exact introducing path and the unchanged S10.4 selector re-proves it. Explicit envelope: 4 evidence documents and 2 tests; later evidence K may update only those exact documents and required task pins.
- Exact delta: automated verification/evidence only.
- GOLDEN: every frozen matrix cell is PASS with exact screenshot/AX/contrast/hash evidence, all brand assets render, common tasks complete, and candidate-vs-S9 comparisons are human-reviewed without erasing S9 baselines.
- ALT-1: any missing matrix cell, overflow/crop, contrast/target/focus/order/localization failure, unreviewed visual delta, or flaky/unbound screenshot fails closed and triggers a smallest causal correction rather than waived acceptance.
- Selectors/budget: `S10_4AutomatedBrandLabTests`, `S10_4AutomatedBrandLabUITests`; F25.
- Terminal/next: next S10.5 only after automated evidence K is accepted.

### S10.5 — Owner-bridged physical experience evidence

- Anchors/start: exact accepted product E from S10.4, frozen owner-operated distribution bridge, and the physical protocol; Codex does not sign, upload, or operate the device.
- Outcome: prepare and validate the bounded owner evidence packet tying the installed build to E and recording physical accessibility, camera/field, force-quit/durability, performance/thermal, Light/Dark/largest-text, and real-device common-task observations.
- Allowed/forbidden: `s10-experience-validation.json`, the exact physical evidence index/receipt paths frozen by activation, and one non-UI contract test. Explicit envelope: 3 evidence documents and 1 test. No app/product/project/asset change, simulated physical PASS, credential/signing material, automatic TestFlight dispatch, upload, or invented owner observation.
- Exact delta: owner-bridged evidence only; missing physical operation stays explicit `NOT_RUN` and blocks completion rather than blocking unrelated static preparation.
- GOLDEN: every required physical task is owner-recorded PASS against the exact build identity with no blocker, and machine validation binds installation/build/artifact/device/observer/timestamp evidence to product E.
- ALT-1: absent/mismatched build identity, inaccessible/unsigned/uninstalled artifact, unresolved blocker, missing observation, or fabricated automation claim fails closed and preserves all evidence.
- Selectors/budget: `S10_5PhysicalExperienceTests`; N8 with UI disabled.
- Terminal/next: next S10.6 only after required owner evidence exists.

### S10.6 — Branded release, store, privacy, supply-chain, and legal evidence lock

- Anchors/start: accepted automated and physical evidence, unchanged product E, descendant K evidence, reviewed store plan, S9 release artifacts, and explicit pending/provided external release facts.
- Outcome: lock App Store screenshot/copy/asset readiness, privacy-manifest consistency, package/runtime supply-chain allowlist, brand-rights/trademark/name/claim/URL status, all six checkpoint receipts, and the final S10 evidence graph without signing/upload/submission.
- Allowed/forbidden: canonical store-readiness/evidence-lock/stage-checkpoint documents, exact store/privacy/supply-chain evidence manifests, S9 release metadata documents only where the branded candidate requires a truthful repository-derived update, and one unit/one UI final branded-candidate test. Explicit envelope override: up to 10 product/evidence files and 2 tests; no feature/schema/behavior change, secret, signing, upload, deployment, App Store mutation, fabricated clearance, or automatic baseline replacement.
- Exact delta: release evidence and truthful metadata only; unresolved live/legal values stay `pending` and release remains blocked.
- GOLDEN: final F25 branded candidate, store slots, privacy/supply-chain inventory, rights grant, separate dated trademark/name/claim/URL evidence, checkpoint E/K/C receipts, hashes, CI artifacts, and one terminal branded screenshot all cross-validate with no unresolved hard gate.
- ALT-1: stale/mismatched E/K/C ancestry, extra runtime asset, missing privacy/store field, unreviewed screenshot, pending/malformed clearance, unsupported claim, or external-value invention fails closed and prevents release-ready status.
- Selectors/budget: `S10_6BrandReleaseTests`, `S10_6BrandReleaseUITests`; F25.
- Terminal/next: phase-end exact-head CI, HANDOFF-only phase close, non-force exact-main fast-forward and exact-main F25; then stop coding for owner-only S9.2/S9.3.

## 10. Owner-only release gates

### S9.2 — Owner-only TestFlight upload and physical iPhone

Owner manually selects the reviewed exact `main` SHA under the private-solo ref rule and dispatches once. The job validates ref/version/build, creates an ephemeral keychain, imports approved signing material, archives, exports, uploads once, and sanitizes evidence. It never retries upload automatically.

CI `.storekit` evidence remains CI evidence. TestFlight uses App Store Connect Sandbox product data and a named Sandbox tester; local `.storekit` fixtures are not claimed on device. Owner verifies fresh install/offline report, real low-light camera/denial/import/Settings recovery, resume, PDF/Share/Files, deletion/backup/restore/Erase, feasible Sandbox purchase/trial/cancel/restore/manage behavior, VoiceOver, default/largest accessibility sizes, 44-point targets, Light/Dark, Increase Contrast, Reduce Transparency, Reduce Motion, live links, and no-sync copy. A blocker becomes a new scoped card; never patch the uploaded commit.

### S9.3 — App Store Connect submission

Owner selects the exact tested build, completes App Privacy from actual binary/network behavior, supplies screenshots/description/keywords/support/privacy/terms/review notes/subscription/age/encryption answers, confirms `AssetRounds: Sign Inspection` as the final App Store title plus the non-claims and fixed subscription configuration, submits manually, and records archive/dSYM, tested SHA/run, App Store build ID, and review outcome. No feature coding occurs here.

## 11. Copy-ready no-planning goal

```text
/goal Complete every remaining coding card through S10.6 in strict runbook and
frozen phase/branch-map order.

The plan is approved. Do not enter /plan, redesign, combine, skip, pre-implement,
improve adjacent code, or invent phase work. Read AGENTS.md, CURRENT_TASK.md,
its exact pinned BUILD_PLAN_V4.md, and its exact pinned runbook before acting.

For every card, run fresh read-only G0. Implement only its outcome, GOLDEN, and
ALT-1; commit and push only its authorized paths to the named phase branch; dispatch
the exact unsigned macOS workflow; and accept only green exact-head CI with complete
evidence. Use one candidate at a time. On terminal failure, inspect logs/artifacts
and either dispatch a fresh-runner candidate at the same exact head or create the
smallest direct-child current-card/CI-harness correction. Repeat with no candidate,
I, K, correction, signature, or watchdog ceiling.

After green CI, append HANDOFF. If autopilot is enabled, the transition flag is yes,
the immediate next card remains inside the exact authorized same-phase span, and every field resolves uniquely under the closed
hydration rule, replace CURRENT_TASK with only that contract, commit/push exactly
HANDOFF plus CURRENT_TASK, run fresh G0, and continue. Resolve ambiguity through
repository/Git/GitHub evidence and never invent a product fact. Before bookkeeping push, require the remote phase ref to equal the
accepted verification head V (E normally; exact green K when the lane applies), use non-force push only, and verify the ref equals the new commit.
At an authorized boundary, commit/push final HANDOFF, verify refs, non-force
fast-forward main to the exact phase-close commit, require UI-enabled exact-main
CI, create only the frozen next branch, hydrate only its first card, run fresh G0,
and continue. Unexpected ref movement, missing evidence, product/compiler/test
failure, and infrastructure recurrence keep the current card active for read-only
diagnosis, waiting, fresh dispatch, or the smallest authorized correction. Never
weaken acceptance, force-push, sign, upload, deploy, or submit. End coding after S10.6 for the
owner-only S9.2/S9.3 gates.
```

## 12. Completion rule

A card completes only with accepted product implementation evidence, green exact verification-head CI, and recorded handoff. A phase completes only after verified non-force fast-forward integration and green CI on the exact resulting `main` verification/phase-close SHA. When infrastructure changes the verification head, record implementation `E` and verification head `K` separately and use accepted `K` as the next base. Current S0's next support head is direct-child K4; K3 phase run `31590956549` is green and K3 main run `31591804256` is a historical readiness-watchdog failure. The first current exact-green phase and exact-main support head becomes S0 verification/phase-close and S1 `P=M`, while S0.1 remains evidenced by I3 and its existing HANDOFF. S10 additionally requires a product head `E`, any descendant evidence head `K`, and a later receipt/bookkeeping `C` with no product-byte mutation after E. Coding automation completes after S10.6's exact-main gate; product release completes only after owner-recorded S9.2/S9.3 evidence. A Windows edit, stale run, divergent branch, plan-only artifact, or upload without physical verification is not completion evidence and feeds diagnosis rather than consuming authority.

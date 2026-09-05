# V23 pre-merge correctness review

Selected task: `V23-REVIEW-20260905`.

Owner request: review V23's implementation and all cards for major defects before future integration, fix demonstrated problems, update active model guidance for Astra, and report readiness and remaining requirements. This is a new review task, not a replay of inherited S9 or an acceptance amendment to historical V23 cards.

## Frozen inputs and isolated output

- Product repository: `https://github.com/Asset-Rounds/AssetRounds.git`.
- V23 base: `acbfb68355f903fe98638b6ef22e4814e7b48328`.
- V23 tree: `47e17fae6b73dccd5029ccf4ac7cca659196f225`.
- Coordination repository: `https://github.com/Asset-Rounds/AssetRounds-v23-coordination.git`.
- Coordination base: `51ef2b3d970a25b4c83df8c8238609316e37034e`.
- Review branch: `codex/v23-premerge-review-20260905`.
- Review worktree: `C:\AssetRounds-v23-premerge-review`.
- V30 observed separately at `06c7e7f49eae20a2d273ce15e98cc2f881fb8510`; its Card 11 remains independent work.

Read-only review covers the full V23 card register, source, tests, project, workflow, and coordination evidence. Product corrections must be supported by a concrete reproducer or source-proven failure, mapped to their causal owner, and listed individually below before editing. No speculative feature, package, backend, entitlement, permission, payment, analytics, or release change is implied by the quality review.

## Current write scope

- `AGENTS.md`: active review selection and Astra routing; preserve historical instructions below it.
- `docs/design/v23/review/CURRENT_REVIEW.md`: current scope and observed evidence.
- `docs/design/v23/review/PREMERGE_REVIEW.md`: findings, corrections, coverage, and remaining integration requirements.
- `docs/design/v23/review/CARD_COVERAGE.md`: all-146-card read-only evidence inventory, with historical statuses preserved.

Additional exact causal source/test paths will be recorded here after diagnosis. Canonical V23 card statuses, sealed plans and receipts, V30 worktree, `C:\AssetRounds`, Phase 10 refs/runs, and `main` are not review mutation targets. No merge or release is performed by this task.

## Diagnosed correction scope

Missing-inner-`try` closure family: only insert required throwing annotations at source-proven calls in these paths; no semantic rewrite:

- `FieldEvidenceApp/Application/Activities/PunchReviewWorkflowCoordinatorV1.swift`
- `FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift`
- `FieldEvidenceApp/Application/Drafts/DraftRecoveryProjectionCoordinatorV1.swift`
- `FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift`
- `FieldEvidenceApp/Application/Reporting/AccessibleDocumentCoordinatorV1.swift`
- `FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift`
- `FieldEvidenceApp/Domain/AssetSemantics/AssetLocatorContractsV1.swift`
- `FieldEvidenceApp/Domain/Content/PrivacyTransformContractsV1.swift`
- `FieldEvidenceApp/Domain/Content/TemporalEvidenceContractsV1.swift`
- `FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift`
- `FieldEvidenceApp/Domain/InspectionKernel/InspectionReviewContractsV1.swift`
- `FieldEvidenceApp/Domain/InspectionKernel/MeasurementIntegrityContractsV1.swift`
- `FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift`
- `FieldEvidenceApp/Domain/InspectionKernel/WorkPacketManifestContractsV1.swift`
- `FieldEvidenceApp/Domain/Labels/AssetLabelContractsV1.swift`
- `FieldEvidenceApp/Domain/Lighting/LightingDayInventoryContractsV1.swift`
- `FieldEvidenceApp/Domain/Models/AssetLocatorPersistenceModelsV1.swift`
- `FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift`
- `FieldEvidenceApp/Domain/Packs/ClientCapabilityContractsV1.swift`
- `FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift`
- `FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift`
- `FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift`
- `FieldEvidenceApp/Domain/Reporting/ShopReportProfileContractsV1.swift`
- `FieldEvidenceApp/Domain/ServiceReliability/AssetServiceReliabilityContractsV1.swift`
- `FieldEvidenceApp/Domain/ServiceRequests/PortableServiceRequestContractsV1.swift`
- `FieldEvidenceApp/Domain/Workflow/ScheduleContractsV1.swift`
- `FieldEvidenceApp/Domain/Workflow/SurveySessionContractsV1.swift`
- `FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift`
- `FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift`
- `FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift`
- `FieldEvidenceApp/Infrastructure/Media/TemporalEvidenceLifecycleAdapterV1.swift`
- `FieldEvidenceApp/Infrastructure/MyDay/MyDayLifecycleAdapterV1.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift`
- `FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/AccessibleDocumentLifecycleAdapterV1.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift`
- `FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift`
- `FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift`
- `FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift`
- `FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift`

Backup duplicate nested release identity: collision-checked insertion in `FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift` and decoder regressions in `FieldEvidenceAppTests/V9_32PackageEvolutionTests.swift`.

Measurement exact-retry recovery: `FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift` and regression tests in `FieldEvidenceAppTests/V9_33MeasurementIntegrityTests.swift`. Validate durable receipts before live revision checks, preserve workspace/invalidation checks, reject divergent mutation reuse, and prove no duplicate effects.

## Verification and truthfulness

Round first-write admission: `FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift`, `RoundSessionMutationV1.init`, has the same nil-predecessor comparison bug. Correct it without relaxing successor checks and add constructor acceptance/rejection regressions in `FieldEvidenceAppTests/V9_70RoundSessionStateTests.swift`. The `commitRoundSession` method in `FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift` may move its existing `currentRevision()` lease validation before a durable-receipt early return; add a released-lease regression in the same round test path. Do not change receipt identity validation or adapter effect matching.

Shop first-write admission: `FieldEvidenceApp/Domain/Reporting/ShopReportProfileContractsV1.swift`, `ShopReportProfileMutationV1.init`, incorrectly compares nil predecessor revision with zero. Correct first-revision handling while preserving positive successor predecessor checks; exercise first-save and stale successor rejection in the same shop tests.

Fresh-Windows-checkout hash stability: `.gitattributes` may add `*.py text eol=lf`. The frozen tooling manifest hashes LF Python blobs, but inherited `* text=auto` plus system `core.autocrlf=true` changes fresh worktree bytes to CRLF and fails hash verification. Restore only clean tracked Python working files from their unchanged index after setting this attribute; do not repin receipts or modify Python source.

Shop report-profile save replay: `FieldEvidenceApp/Application/Reporting/ShopReportProfileCoordinatorV1.swift`, the `commitShopReportProfile` method in `FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift`, and `FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests.swift`. A successful exact retry is incorrectly validated as a successor of itself. Permit exact validated-history replay only through typed durable receipt validation; preserve lease checks, reject divergent mutation reuse and stale new writes, including replay after a later successor. No protocol expansion.

Native diagnostic scope: `Scripts/ci-selection.json` selects only the 15 newly added backup, measurement, shop-profile, and round-session regression methods for `V23-REVIEW-20260905`, N8 / UI false. Use the existing `.github/workflows/ios-ci.yml` unchanged on this review branch in `Asset-Rounds/AssetRounds`, with its pinned macOS-26/Xcode26.6 build17F113/iPhone17-iOS26.2 environment and checksummed artifacts. A scoped commit/push and one exact-head diagnostic dispatch are ordinary verification steps for these corrections. This is not V23 acceptance or permission to merge, alter Phase 10 runs, or use owner release workflows. Record terminal evidence before any evidence-driven follow-up; do not dispatch repeated known failures or duplicate active jobs.

Windows may perform source, schema, JSON, Python, and deterministic checks. Native iOS build/test claims require the hosted macOS route and an explicit review selector. Static preparation and source review never establish merge or release acceptance. Do not run historical generators in apply mode or repin expected values merely because this review has a different branch/head. Preserve failed and superseded evidence.

Final review reports must distinguish: all-card inventory, selected deep code review, fixes made, tests actually executed, native checks pending, owner/deferred cards, and compatibility checks required when Phase 10 and V23 are combined. No claim of zero bugs or whole-program exhaustive review is permitted without supporting evidence.

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

## Compiler-confirmed correction batch 2

### Owner-requested safe turn boundary

The owner requested ending this turn to select Astra Medium. All agents stopped at safe file boundaries; no hosted run is active. Base correction commit `074dba9eb40af6be12787e7ddfeb6751d4011832` is pushed. Its native diagnostic `33979981288` failed product-source parsing and skipped all tests. Partial batch 2 is saved as a nonaccepting checkpoint; resume it rather than restarting the audit or altering Phase 10.

Saved batch-2 edits: root's WorkspaceWriterV1 guard parentheses and ShopProfileOpenEvidenceHandoffView guard parentheses; data-integrity lane's V4BackupContracts.swift only; measurement lane's 16 domain paths; infrastructure lane's 10 paths. `git diff --check` passes, but independent review and native verification remain pending. No half-applied patch was reported.

Remaining work:

1. Reuse `v23_data_integrity_audit`: finish BackupCanonicalEncoderV1.swift, BackupImportService.swift, BackupPackageValidatorV1.swift, BackupRestoreService.swift. Review its saved V4BackupContracts syntax corrections.
2. Reuse `v23_runtime_integration_audit`: no batch-2 edits yet in its 10 paths (Domain/Mutation x2, InspectionKernel x3, Models x2, FunctionalRelationships, Activities, Drafts). Apply diagnosed declaration separators/guard parentheses, close WorkspaceMutationContractsV1 predecessorIdentity getter's missing brace, and add missing derivative guard else using the adjacent invalidPlan failure contract; preserve both predicates.
3. Independently review `v23_measurement_regression` saved 16-domain-path corrections (including only the stray top-level duplicate reminder validation removal; active validation retained).
4. Independently review `v23_native_infra_syntax` saved 10 infrastructure paths, especially named outer closure binding in LocalChangeJournal, restored missing guard in WorkspaceWriterAdapter, and remaining same-guard trailing closures in LocalSearchIndexStore after line 130. The latter may need additional parentheses before the next run.
5. Finish checksum audit via `v23_merge_status_audit` if its final result has not yet arrived. Root must inspect complete build evidence, scope-check all changes, and only then commit a finished direct-child correction and dispatch a fresh exact-head native diagnostic. Do not rerun the failed run ID or repin old V23 receipts.

The complete all-card inventory and initial fixes are preserved in PREMERGE_REVIEW and CARD_COVERAGE. Model instructions do not change the app-selected model; reuse available agent context with the owner's new primary selection.

Native run `33979981288` on `074dba9eb40af6be12787e7ddfeb6751d4011832` failed Swift parsing before tests. Correct only diagnosed syntax (guard trailing-closure parentheses, declaration separators, balanced expressions, interpolation escapes, and required lexical spacing) at the reported sites in these exact paths, preserving predicates, ordering and data semantics. The complete checksummed build log is under `C:\AssetRounds-v23-review-evidence\33979981288\ios-ci-33979981288-1\build-smoke.log`. No project exclusions, test weakening, schema changes or historical receipt edits. After scoped corrections and independent checks, a fresh same-workflow diagnostic on the direct-child review head is authorized; never rerun the old failed run ID.

- `FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift` (reported lines 1123).
- `FieldEvidenceApp/Domain/Activities/ActivityContractFamiliesV2.swift` (reported lines 1966, 1967).
- `FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift` (reported lines 2699, 2754, 2928, 2929, 2930, 3530, 3531, 3800, 3801, 3802, 3803, 4138, 4318, 4511, 4744, 4839, 5271, 5302, 5334, 5366, 5369, 5370, 5371, 5372, 5373, 5374, 5375, 5377, 5378, 5415).
- `FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift` (reported lines 256).
- `FieldEvidenceApp/Domain/FunctionalRelationships/FunctionalRelationshipContractsV1.swift` (reported lines 508, 509).
- `FieldEvidenceApp/Domain/ImportExport/ImportBulkContractsV1.swift` (reported lines 1498, 1499, 1500, 1501, 1502).
- `FieldEvidenceApp/Domain/InspectionKernel/InspectionReviewContractsV1.swift` (reported lines 157, 159, 162, 165, 179, 180, 184, 197, 285).
- `FieldEvidenceApp/Domain/InspectionKernel/MeasurementIntegrityContractsV1.swift` (reported lines 373, 374).
- `FieldEvidenceApp/Domain/InspectionKernel/WorkPacketManifestContractsV1.swift` (reported lines 215).
- `FieldEvidenceApp/Domain/Lighting/LightingContractsV1.swift` (reported lines 530).
- `FieldEvidenceApp/Domain/Lighting/LightingDayInventoryContractsV1.swift` (reported lines 190, 350).
- `FieldEvidenceApp/Domain/Models/ReviewAndCorrectiveActionPersistenceModelsV1.swift` (reported lines 4, 5, 6, 7, 8).
- `FieldEvidenceApp/Domain/Models/WorkPacketManifestPersistenceModelsV1.swift` (reported lines 31, 32, 33, 34, 35).
- `FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift` (reported lines 989, 992, 1174).
- `FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift` (reported lines 1355, 1364, 1373, 1389, 1391, 1400, 1403, 1627, 1749).
- `FieldEvidenceApp/Domain/OfflineReadiness/OfflineReadinessManifestContractsV1.swift` (reported lines 882).
- `FieldEvidenceApp/Domain/Packs/ClientCapabilityContractsV1.swift` (reported lines 10, 11, 29, 60).
- `FieldEvidenceApp/Domain/Packs/FieldReferencePackContractsV1.swift` (reported lines 30, 113).
- `FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift` (reported lines 116, 142, 263, 298, 300, 370, 372).
- `FieldEvidenceApp/Domain/Recovery/RecoveryCenterContractsV1.swift` (reported lines 353, 354, 355).
- `FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift` (reported lines 215, 216, 242, 243, 244, 245, 247, 248, 249, 250, 251, 252).
- `FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift` (reported lines 381).
- `FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift` (reported lines 2598, 2599, 2600).
- `FieldEvidenceApp/Domain/Search/SearchContractsV1.swift` (reported lines 1655, 1656, 1657, 1790, 1791, 1792).
- `FieldEvidenceApp/Domain/VoiceCapture/StructuredVoiceCaptureContractsV1.swift` (reported lines 284).
- `FieldEvidenceApp/Domain/Workflow/RecurringRoundExperienceContractsV1.swift` (reported lines 279).
- `FieldEvidenceApp/Domain/Workflow/ScheduleContractsV1.swift` (reported lines 312, 388).
- `FieldEvidenceApp/Domain/WorkResources/WorkResourceContractsV1.swift` (reported lines 126).
- `FieldEvidenceApp/Features/Reporting/ShopProfileOpenEvidenceHandoffView.swift` (reported lines 237, 238, 239, 240).
- `FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift` (reported lines 782, 783, 785, 791, 1284, 1328, 1338, 1349, 1389, 1421, 1663).
- `FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift` (reported lines 1661).
- `FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift` (reported lines 155, 220, 243, 271, 2323, 2398, 2399, 3936, 3942, 4797, 4825, 4850, 4888, 4925).
- `FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift` (reported lines 4034, 4880, 4881, 4882, 5180, 5181, 5182, 13454, 13521).
- `FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift` (reported lines 83, 84).
- `FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift` (reported lines 3204, 3205, 3206, 3207, 3210).
- `FieldEvidenceApp/Infrastructure/Drafts/DraftAttachmentStagingAdapterV1.swift` (reported lines 1110).
- `FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift` (reported lines 1447, 1467).
- `FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift` (reported lines 2611, 3966).
- `FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift` (reported lines 910, 911, 912).
- `FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift` (reported lines 3206, 3715, 3972).
- `FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift` (reported lines 849, 850, 851, 1813, 1814, 1815).
- `FieldEvidenceApp/Infrastructure/Rounds/RoundSessionLifecycleAdapterV1.swift` (reported lines 467).
- `FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift` (reported lines 128, 129, 130).

#!/usr/bin/env python3
"""Deterministic static contract corpus and evidence builders for V23-P03-C18."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C18"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 55
TITLE = "Semantic package diff, deterministic draft upgrade preview, sandbox conformance, and immutable promotion receipt"
BASE_HEAD = "38b5bd807bb7e1096e015077f72a9e25b8b06b6a"
BASE_TREE = "8d36b480b0103993ad0c5dab6df055bf63b2da8d"
COORDINATION_HEAD = "65b428cf4879a06f0327f89965ede62161a8c358"
COORDINATION_TREE = "406cf4cc91a749f59c380ea2f1aa692e3019a050"
COORDINATION_LEDGER_DIGEST = "ce7f8b931b31d2a21837773374900b0c039cb7253e1eec40b1e2b07dea0b74cd"
COORDINATION_PROJECTION_DIGEST = "902a00237488bc9da4775e1b3c4f8346600fc7c29dc3b64a57aef7a50bbd424f"
COORDINATION_CAS_SEQUENCE = 234
HYDRATION_TRANSITION_SEQUENCE = 234
HYDRATION_TRANSITION_DIGEST = "0c126dcf08d61f7188030b402424bc760f00eec76299f1c214bd9c59c6d12526"
CONTEXT_DIGEST = "5c82d6b49bf674350b158c7fd0f6daff18a080388482a92865bfe79675aa9e6a"
FENCE_DIGEST = "eab54375fd87a7abb1c36093fbe693d27c32acc0fdbfa85ba1248b28a2ba06ae"
PREREQUISITE_DIGEST = "9dadeb578b383a8fb07d2d9d9302fc800c06b29832ef64fbe335a116360e6330"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "6a1dad735ea873f62f864ab81026499e241313c7b2af79f012158fdd3f954580"
REGISTER_ROW_UTF8_LENGTH = 316
DOSSIER_SHA256 = "6c41feb360c45a9bc78c6ba2dea5ab129b8b7d6110bc3aee9003c8b81666f6b3"
DOSSIER_UTF8_LENGTH = 7268
INHERITED_V21_BLOCK_SHA256 = "3e858fdd4b0f8caf7f29431c4314921b801ac06f01b0553044096f233ce9a766"
INHERITED_V21_BLOCK_UTF8_LENGTH = 10820

SCHEMA_PATH = "Scripts/v23/package-evolution.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C18PackageEvolutionContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C18PackageEvolutionEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C18BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C18-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c18_contracts.py",
    "Scripts/v23/generate_p03_c18_contracts.py",
    "Scripts/v23/verify_p03_c18_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

EXISTING_PATHS = (
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Domain/Packs/SignPack.swift",
    "FieldEvidenceApp/Domain/Packs/SignPackLoader.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Infrastructure/Packs/ShippingIlluminatedSignAdapterV1.swift",
    "FieldEvidenceApp/Resources/Packs/IlluminatedSignPack.json",
    "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceAppTests/S1PackTokenTests.swift",
    "FieldEvidenceAppTests/S3_1DraftSchemaTests.swift",
    "FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift",
    "FieldEvidenceAppTests/S6_1DeletionGraphTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_1SecondPackZeroForkTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_11PackRegistryTests.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_19LocalSearchTests.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/V9_30FieldDraftResilienceTests.swift",
    "FieldEvidenceAppTests/V9_31IntegrationEventProjectionTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Packs/PackageEvolutionContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/PackageEvolutionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Packs/PackageEvolutionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/PackageEvolutionLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift",
    "FieldEvidenceAppTests/V9_32PackageEvolutionTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/PackageEvolution/V21P03C18PackageEvolutionCorpusV1.json",
    *SCRIPT_PATHS,
    SCHEMA_PATH,
    CONTRACT_PATH,
    EVIDENCE_PATH,
    BRAND_PATH,
    MANIFEST_PATH,
)
# These four baseline package paths are intentionally preserved byte-for-byte
# by the C18 candidate. They remain inside the allowed fence but are not
# required implementation changes.
PRESERVED_BASELINE_PATHS = (
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Domain/Packs/SignPack.swift",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Resources/Packs/IlluminatedSignPack.json",
)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
FULL_FENCE_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
SOURCE_REFERENCE_PATHS = EXISTING_PATHS
AUTHORITY_REFERENCE_PATHS = (
    "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md",
)

_OVERLAP_COUNTS = {
    "V23-P00-C11": 1, "V23-P01-C01": 3, "V23-P01-C02": 7, "V23-P01-C03": 6,
    "V23-P01-C04": 3, "V23-P01-C05": 11, "V23-P01-C06": 21, "V23-P01-C07": 6,
    "V23-P02-C01": 6, "V23-P02-C02": 27, "V23-P02-C03": 21, "V23-P02-C04": 6,
    "V23-P02-C05": 9, "V23-P02-C06": 2, "V23-P02-C07": 24, "V23-P02-C08": 6,
    "V23-P02-C09": 5, "V23-P03-C01": 8, "V23-P03-C02": 4, "V23-P03-C03": 1,
    "V23-P03-C06": 4, "V23-P03-C07": 3, "V23-P03-C08": 11, "V23-P03-C09": 38,
    "V23-P03-C10": 2, "V23-P03-C11": 5, "V23-P03-C12": 29, "V23-P03-C13": 60,
    "V23-P03-C14": 60, "V23-P03-C15": 61, "V23-P03-C16": 6, "V23-P03-C17": 31,
    "V23-P03-C35": 35, "V23-P03-C36": 59, "V23-P03-C38": 43, "V23-P03-C39": 49,
    "V23-P03-C40": 54, "V23-P03-C41": 63,
}
PRIOR_FENCE_OVERLAPS = tuple(
    {"cardID": card, "fenceDigest": "BOUND_TO_C18_PRIOR_FENCE_PROOF", "disposition": "REPROOF_REQUIRED", "overlapCount": count}
    for card, count in _OVERLAP_COUNTS.items()
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 55,
    "priorOwnedPathCount": 924,
    "overlapCount": 790,
    "authorizedOverlapCount": 790,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = (
    "PackageSemanticGraphV1", "PackageSemanticDiffV1",
    "DraftUpgradePlanV1", "PackageSandboxRunV1", "PackagePromotionReceiptV1",
    "ActivePackageRegistryPointerV1", "PromotedPackageReleaseV1", "PackageEvolutionCompatibilityV1",
)
PACKAGE_GRAPH_KINDS = ("PACKAGE", "SCHEMA", "RECORD", "FIELD", "RELATION", "PRESENTATION", "LOCALIZATION", "ACCESSIBILITY")
DIFF_DISPOSITIONS = ("NO_CHANGE", "ADDITIVE_DRAFT_SAFE", "DRAFT_MIGRATION_REQUIRED", "ACTIVE_SESSION_INCOMPATIBLE", "INVALID")
SANDBOX_STATES = ("NOT_RUN", "PASSED", "FAILED_CLOSED", "INTERRUPTED", "REBUILT")
PROMOTION_STATES = ("PREVIEW", "PROMOTED", "ROLLED_BACK", "FORWARD_FIX_REQUIRED", "VOID")
LIFECYCLE_MODES = ("PERSISTENT_V17", "NONPERSISTENT_DRAFT_PREVIEW", "BOUNDED_SANDBOX", "IMMUTABLE_PROMOTION_RECEIPT")
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V17_RECORDS16", "SOLE_WRITER_TRANSACTION", "MIGRATION_AND_FORWARD_FIX",
    "BACKUP_REPLACE_RESTORE", "CLONE_FORK_GENERATION", "IMPORT_EXPORT_PREVIEW",
    "JOURNAL_REPLAY_CHECKPOINT", "DELETE_ERASE_RETENTION", "LOCAL_SEARCH_REBUILD",
    "REPORT_SNAPSHOT_OPEN_JSON", "PRIVACY_PROGRESSIVE_DISCLOSURE", "INTERRUPTION_IDEMPOTENT_RECEIPTS",
)
FORBIDDEN_CLAIMS = (
    "REMOTE_CATALOG_DELIVERY_OR_ACCOUNT_ENTITLEMENT", "PROVIDER_URL_CREDENTIAL_OR_SIGNATURE",
    "SCRIPT_ENGINE_GENERIC_JSON_EAV_OR_SECOND_STORE", "ACTIVE_COMPLETED_REWRITE_OR_HYBRID_ROLLBACK",
    "NO_UI_BEFORE_S10_RECONCILIATION", "LEGAL_REGULATORY_TAMPERPROOF_OR_NONREPUDIATION",
    "NATIVE_IPAD_SURFACE_OR_PUBLIC_METADATA", "SIGNING_TESTFLIGHT_APP_STORE_OR_DEPLOYMENT",
    "REMOTE_EMAIL_BILLING_ANALYTICS_OR_TELEMETRY", "S10_RELEASE_OR_BRAND_APPROVAL",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
# These are the canonical selector names for the C18 test lane.  The verifier
# binds them to the materialized V9_32 test file before complete acceptance.
TEST_METHODS = (
    "testV23P03C18G01ClassifiesAllFiveTypedClassesDeterministically",
    "testV23P03C18A01ExplicitDraftOptInRunsBothSandboxShapes",
    "testV23P03C18H01StaleFinalPartialAndDivergentInputsFailClosed",
    "testV23P03C18I01EveryPromotionBoundaryRetainsCompleteAuthority",
    "testV23P03C18R01RecoveryLifecycleSearchAndBrandExclusionsAreExact",
)
SOURCE_CONTRACT_TOKENS = (
    CARD, "V21-P03-C18", "PromotedPackageReleaseV1", "PackageSemanticDiffV1",
    "DraftUpgradePlanV1", "PackageSandboxRunV1", "immutable promotion receipt",
)
REQUIRED_BEHAVIORS = (
    {"id": "SEMANTIC_DIFF", "contract": "PackageSemanticDiffV1", "requirement": "Typed canonical package graphs compare independent of locale, order, whitespace, and serializer bytes; unchanged, additive draft-safe, migration-required, active-session-incompatible, and invalid outcomes are distinct.", "evidence": "C18-S01"},
    {"id": "DRAFT_PREVIEW", "contract": "DraftUpgradePlanV1", "requirement": "The draft upgrade preview is nonpersistent, nonfinal, exact-source-revision bound, and applies only through the existing C36 draft writer.", "evidence": "C18-S02"},
    {"id": "SANDBOX_CONFORMANCE", "contract": "PackageSandboxRunV1", "requirement": "A bounded local sandbox validates two package shapes, lifecycle integration, localization, accessibility, report, backup, restore, search, replay, and brand/state conformance without activation.", "evidence": "C18-S03"},
    {"id": "PROMOTION_RECEIPT", "contract": "PackagePromotionReceiptV1", "requirement": "One canonical writer transaction binds package bytes, semantic diff, sandbox result, actor authority, exact candidate, registry pointer, and rollback compatibility.", "evidence": "C18-S04"},
    {"id": "ACTIVE_POINTER", "contract": "ActivePackageRegistryPointerV1", "requirement": "The active pointer changes only with a durable immutable promotion receipt and never mixes old and new generations.", "evidence": "C18-S05"},
    {"id": "V17_LIFECYCLE", "contract": "PersistentSchemaV17", "requirement": "Schema V17 and records 16 migration, backup/restore, clone/fork, import/export, replay, search, delete/Erase, compatibility, and forward-fix dispositions are explicit.", "evidence": "C18-S06"},
    {"id": "FAIL_CLOSED", "contract": "PackageEvolutionCompatibilityV1", "requirement": "Unknown, corrupt, stale, protected-data, storage, cancellation, permission, capability, concurrency, and forged receipt conditions fail closed without partial canonical success.", "evidence": "C18-S07"},
    {"id": "STATIC_BOUNDARY", "contract": "V23-P03-C18", "requirement": "This lane is PASS_STATIC_PROVISIONAL and native, hosted, adoption, acceptance, and release flags remain false.", "evidence": "C18-B01"},
)
EVIDENCE_CASES = (
    {"id": "C18-S01", "kind": "SEMANTIC_DIFF", "assertion": "Golden package graphs produce a stable canonical diff, digest, and ordered receipt independent of presentation bytes."},
    {"id": "C18-S02", "kind": "DRAFT_PREVIEW", "assertion": "Alternate legacy-compatible and draft-safe upgrades remain preview-only until canonical writer promotion."},
    {"id": "C18-S03", "kind": "SANDBOX", "assertion": "Bounded sandbox conformance covers two package shapes and all inherited lifecycle boundaries without activating a package."},
    {"id": "C18-S04", "kind": "PROMOTION", "assertion": "Promotion receipt and active pointer are committed atomically and remain immutable under rollback or forward fix."},
    {"id": "C18-S05", "kind": "POINTER", "assertion": "Stale, forged, mismatched, concurrent, and hybrid pointer updates fail without partial canonical state."},
    {"id": "C18-S06", "kind": "V17_LIFECYCLE", "assertion": "Migration, backup, restore, clone, fork, import, export, journal replay, search, delete, Erase, and compatibility preserve exact bytes and identity."},
    {"id": "C18-S07", "kind": "HOSTILE", "assertion": "Unknown schema, duplicate identity, changed source revision, incompatible active session, protected data, cancellation, and storage failure return typed closed outcomes."},
    {"id": "C18-F01", "kind": "PATH_FENCE", "assertion": "The hydrated fence is exactly 107 paths: 92 existing and 15 new, with zero overlap against the frozen S10 reservation."},
    {"id": "C18-B01", "kind": "STATIC_BOUNDARY", "assertion": "All activation and release flags remain false pending later acceptance and S10 reconciliation."},
)
SOURCE_PROJECTION = {
    "registerRows": ['| 55 | <a id="v23-p03-c18-register"></a>[`V23-P03-C18`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c18) | Semantic package diff, deterministic draft upgrade preview, sandbox conformance, and immutable promotion receipt | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C10`, `V23-P03-C17` | `REFINED_WITHOUT_LOSS` |'],
    "registerSectionSHA256": REGISTER_SECTION_SHA256,
    "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256,
    "registerRowUTF8Length": REGISTER_ROW_UTF8_LENGTH,
    "dossierSHA256": DOSSIER_SHA256,
    "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
    "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True,
    "facetRowCount": 1,
    "canonicalRecordWriterOwnershipRowCount": 4,
    "facetManifestDigest": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001", "V23-POL-HIG-001", "V23-POL-A11Y-001", "V23-POL-L10N-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C18).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["FJ16"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1", "P03ShippingSurfaceSetV1", "P04BrandClosureSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1", "FJ16"],
    "invalidationConsumers": ["V23-P03-C21", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
    "optionalCapabilityProviders": ["NONE"],
    "reservedLegacyOwnerReconciliationDebtCount": 0,
    "reservedLegacyOwnerReconciliationDebtPaths": [],
    "reservedLegacyRawWriteViolationCount": 0,
    "reservedLegacyRawWriteViolationPaths": [],
    "provisionalZeroViolationClosureClaimed": False,
    "canonicalRegisterDigest": "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd",
    "directGraphDigest": "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae",
    "selectorManifestDigest": "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2",
    "relationManifestDigest": "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4",
    "dependencyDispositionDigest": "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c",
    "impactManifestDigest": "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b",
}
DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 2,
    "nonreleaseSpecialEdgeApplied": False,
    "canonicalRelationPreserved": True,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "predecessors": [
        {"cardID": "V23-P03-C10", "attemptID": 1, "candidateHead": "3777bfc1b7800f808871337ddec533f171a6dc39", "candidateTree": "d3b22a2116f16c693c57d590ed9361dc93fe5e78", "checkpointDigest": "bc90541801925613b7ce7442169933c09aabb9308a3308396808f83e6be349d1", "verificationReceiptDigest": "861e16483da58262c6cf451cbe1f3ad9520af42c5128e281dc4fca54127d0762", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C10_HEAD"},
        {"cardID": "V23-P03-C17", "attemptID": 1, "candidateHead": BASE_HEAD, "candidateTree": BASE_TREE, "checkpointDigest": "3511f3a7fad741bf639dbfae0a22e0cddc1e8a0185ddfb8b4360262306d43b7f", "verificationReceiptDigest": "1ddff8c2eee58e3b7984bb8986356015fc84886135fe6dcc7a72b857cc32072a", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C17_HEAD"},
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}
SEMANTIC_SCOPE = {
    "durableOwner": ["PromotedPackageReleaseV1", "PackageSandboxRunV1", "PackagePromotionReceiptV1", "ActivePackageRegistryPointerV1", "PersistentSchemaV17"],
    "atomicAuthorityPolicy": "BOUNDED_PACKAGE_BYTES_IMMUTABLE_SANDBOX_RUN_IMMUTABLE_PROMOTION_RECEIPT_AND_ACTIVE_POINTER_COMMIT_IN_ONE_SWIFTDATA_TRANSACTION_USING_THE_SOLE_CANONICAL_WRITER",
    "diffPolicy": "PACKAGE_SEMANTIC_DIFF_V1_TYPED_CANONICAL_GRAPH_ONLY_NO_CHANGE_ADDITIVE_DRAFT_SAFE_DRAFT_MIGRATION_REQUIRED_ACTIVE_SESSION_INCOMPATIBLE_OR_INVALID_INDEPENDENT_OF_LOCALE_ORDER_WHITESPACE_AND_SERIALIZER_BYTES",
    "draftPolicy": "DRAFT_UPGRADE_PLAN_V1_IS_NONPERSISTENT_EXPLICIT_NONFINAL_EXACT_SOURCE_REVISION_PREVIEW_AND_APPLIES_ONLY_THROUGH_EXISTING_C36_DRAFT_WRITER_ACTIVE_AND_FINALIZED_RECORDS_REMAIN_PINNED",
    "sandboxPolicy": "NONACTIVATING_BOUNDED_TWO_SHAPE_SCHEMA_GRAPH_LOCALIZATION_REPORT_OPEN_JSON_BACKUP_RESTORE_DELETE_ERASE_EXPORT_SEARCH_REBUILD_REPLAY_CLASSIFICATION_BRAND_AND_STATE_CONFORMANCE",
    "promotionPolicy": "IMMUTABLE_RECEIPT_BINDS_PACKAGE_BYTES_DIFF_SANDBOX_REGISTRY_POINTER_ACTOR_AUTHORITY_EXACT_HEAD_AND_ROLLBACK_COMPATIBILITY_WITH_OLD_OR_NEW_RECOVERY_NEVER_HYBRID",
    "lifecyclePolicy": "V17_RECORDS16_ZERO_INVENTION_FROM_V16_BACKUP_RESTORE_CLONE_FORK_IMPORT_EXPORT_JOURNAL_REPLAY_SEARCH_DELETE_ERASE_RETENTION_COMPATIBILITY_AND_FORWARD_FIX_CLOSED",
    "forbiddenPolicy": "NO_UI_BEFORE_S10_RECONCILIATION_NO_REMOTE_CATALOG_DELIVERY_ACCOUNT_ENTITLEMENT_PROVIDER_URL_CREDENTIAL_SIGNATURE_SCRIPT_ENGINE_GENERIC_JSON_EAV_SECOND_STORE_SECOND_WRITER_OR_ACTIVE_COMPLETED_REWRITE",
    "s10Policy": "EXACT_NINETY_EIGHT_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP_AND_FJ16_VISIBLE_UI_DEFERRED",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

REQUIRED_BEHAVIORS = tuple(REQUIRED_BEHAVIORS)
CORPUS: dict[str, Any] = {
    "schema": "V21P03C18PackageEvolutionCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "persistentSchemaVersion": 17,
    "recordsSchemaVersion": 16,
    "persistentPackageEvolutionKindCount": 5,
    "migrationInventedPackageEvolutionCount": 0,
    "requiredContractNames": list(CONTRACT_NAMES),
    "packageGraphKinds": list(PACKAGE_GRAPH_KINDS),
    "diffDispositions": list(DIFF_DISPOSITIONS),
    "sandboxStates": list(SANDBOX_STATES),
    "promotionStates": list(PROMOTION_STATES),
    "lifecycleModes": list(LIFECYCLE_MODES),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    "evidenceCases": list(EVIDENCE_CASES),
    "persistence": {
        "schemaRelease": "PERSISTENT_SCHEMA_V17_PACKAGE_EVOLUTION",
        "schemaVersion": 17,
        "recordsSchemaVersion": 16,
        "mode": "NEW_SCHEMA_VERSION",
        "migrationRequired": True,
        "backupRestoreRequired": True,
        "deleteEraseRequired": True,
        "exportReportRequired": True,
        "canonicalWriter": "V23-P02-C01",
        "canonicalSourceOfTruth": ["PromotedPackageReleaseV1", "PackagePromotionReceiptV1", "ActivePackageRegistryPointerV1"],
        "persistedFamilies": ["PromotedPackageReleaseV1", "PackageSandboxRunV1", "PackagePromotionReceiptV1", "ActivePackageRegistryPointerV1"],
        "nonPersistentFamilies": ["DraftUpgradePlanV1", "PackageSandboxPreviewV1"],
        "currentProjectionRowCount": 0,
        "providerRows": 0,
        "secondStore": False,
        "secondWriter": False,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V17_WRITE",
        "forwardFix": "IMMUTABLE_RECEIPT_BOUND_ROLLBACK_TO_OLD_OR_NEW_GENERATION_NEVER_HYBRID",
    },
    "graphCases": [
        {"id": "golden-unchanged", "disposition": "NO_CHANGE", "sourceRevision": 16, "targetRevision": 16, "canonicalDigest": "1" * 64},
        {"id": "alternate-additive-draft", "disposition": "ADDITIVE_DRAFT_SAFE", "sourceRevision": 16, "targetRevision": 17, "canonicalDigest": "2" * 64},
        {"id": "migration-required", "disposition": "DRAFT_MIGRATION_REQUIRED", "sourceRevision": 16, "targetRevision": 17, "canonicalDigest": "3" * 64},
        {"id": "active-session-incompatible", "disposition": "ACTIVE_SESSION_INCOMPATIBLE", "sourceRevision": 16, "targetRevision": 17, "canonicalDigest": "4" * 64},
        {"id": "invalid-duplicate-identity", "disposition": "INVALID", "sourceRevision": 16, "targetRevision": 17, "canonicalDigest": "5" * 64},
    ],
    "sandboxCases": [
        {"id": "two-shape-schema", "state": "PASSED", "activation": False, "receiptDisposition": "PREVIEW_ONLY"},
        {"id": "localization-accessibility", "state": "PASSED", "activation": False, "receiptDisposition": "PREVIEW_ONLY"},
        {"id": "backup-restore-replay", "state": "PASSED", "activation": False, "receiptDisposition": "PREVIEW_ONLY"},
        {"id": "provider-absence", "state": "FAILED_CLOSED", "activation": False, "receiptDisposition": "NO_PROVIDER_STATE"},
    ],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED_NO_PARTIAL_CANONICAL_SUCCESS"} for case_id in (
        "unknown-schema-version", "duplicate-package-identity", "changed-source-revision", "stale-draft-preview", "forged-sandbox-receipt",
        "forged-active-pointer", "cross-workspace-pointer", "active-session-incompatible", "hybrid-old-new-generation", "oversized-package",
        "provider-catalog-request", "remote-delivery-request", "second-writer-or-store", "script-engine-request", "protected-data-lock",
    )],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "RETRY_IDEMPOTENT_NO_PARTIAL_POINTER"} for case_id in (
        "crash-before-diff", "crash-after-diff-before-sandbox", "crash-after-sandbox-before-receipt", "crash-after-receipt-before-pointer",
        "migration-interruption", "backup-interruption", "restore-interruption", "delete-erase-interruption", "replay-interruption",
    )],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "EXACT_OLD_OR_NEW_GENERATION_REPLAY_NO_HYBRID"} for case_id in (
        "rollback-old-generation", "forward-fix-new-generation", "drop-preview-cache", "rebuild-sandbox-result", "restore-after-interruption",
        "clone-fork-generation", "import-export-roundtrip", "search-rebuild", "journal-replay-from-zero",
    )],
    "claims": {claim: False for claim in (*FORBIDDEN_CLAIMS, "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit")},
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _git_blob(root: Path, relative: str) -> bytes:
    return subprocess.run(["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"], check=True, capture_output=True).stdout


def source_artifacts(root: Path) -> list[dict[str, Any]]:
    return [{"path": path, "source": "BASE_HEAD_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)} for path in SOURCE_REFERENCE_PATHS]


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    return [{"path": path, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)} for path in AUTHORITY_REFERENCE_PATHS]


def _schema_for_value(value: Any) -> dict[str, Any]:
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"type": "boolean"}
    if isinstance(value, int):
        return {"type": "integer"}
    if isinstance(value, float):
        return {"type": "number"}
    if isinstance(value, str):
        return {"type": "string"}
    if isinstance(value, list):
        result: dict[str, Any] = {"type": "array", "minItems": len(value), "maxItems": len(value)}
        if value:
            shapes = {_schema_for_value(item).__repr__(): _schema_for_value(item) for item in value}
            result["items"] = next(iter(shapes.values())) if len(shapes) == 1 else {"anyOf": [shapes[key] for key in sorted(shapes)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(type(value))


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/package-evolution.schema.json", "title": "V23 P03 C18 Package Evolution Corpus"})
    return document


def _flags() -> dict[str, bool]:
    return {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False, "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False}


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION", "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST, "fullFencePaths": list(PATH_FENCE),
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "hydrationTransitionSequence": HYDRATION_TRANSITION_SEQUENCE,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST, "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C10", "V23-P03-C17"], "nextCard": "V23-P03-C19",
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "PERSISTENT_SCHEMA_V17_PACKAGE_EVOLUTION",
        "recordSchemaVersion": 16, "schemaBehaviorDelta": True, "migrationBehaviorDelta": True, "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True, "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V17_WRITE", "uiSurfaceDelta": False, "brandSurfaceDelta": True,
        "nativeCompileRan": False, "hostedDispatchEnabled": False, "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True, "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "pathFenceDigest": FENCE_DIGEST, "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "s10FenceOverlapPaths": []}


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"blueprintPath": AUTHORITY_REFERENCE_PATHS[0], "foundationPath": AUTHORITY_REFERENCE_PATHS[1], "sourceProjection": SOURCE_PROJECTION, "sourceTokens": list(SOURCE_CONTRACT_TOKENS), "requiredContractNames": list(CONTRACT_NAMES), "lineage": "REFINED_WITHOUT_LOSS", "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows}


def _required_semantics() -> dict[str, Any]:
    return {"contractNames": list(CONTRACT_NAMES), "packageGraphKinds": list(PACKAGE_GRAPH_KINDS), "diffDispositions": list(DIFF_DISPOSITIONS), "sandboxStates": list(SANDBOX_STATES), "promotionStates": list(PROMOTION_STATES), "lifecycleModes": list(LIFECYCLE_MODES), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": list(FORBIDDEN_CLAIMS)}


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    return _sealed({"schema": "V23P03C18PackageEvolutionContractV1", "artifact": "V23P03C18PackageEvolutionContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "schemaArtifact": schema_row, "sourceContract": _source_contract(source_rows, authority_rows), "semanticScope": SEMANTIC_SCOPE, "requiredSemantics": _required_semantics(), "persistenceBoundary": CORPUS["persistence"], "requiredLifecycle": list(LIFECYCLE_DIMENSIONS), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "successor": {"cardID": "V23-P03-C19", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {"contractNames": list(CONTRACT_NAMES), "packageGraphKinds": list(PACKAGE_GRAPH_KINDS), "diffDispositions": list(DIFF_DISPOSITIONS), "sandboxStates": list(SANDBOX_STATES), "promotionStates": list(PROMOTION_STATES), "lifecycleModes": list(LIFECYCLE_MODES), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "requiredLifecycle": list(LIFECYCLE_DIMENSIONS)}
    return _sealed({"schema": "V23P03C18PackageEvolutionEvidenceReceiptV1", "artifact": "V23P03C18PackageEvolutionEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows), "schemaArtifact": schema_row, "contractArtifact": contract_row, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics), "persistenceBoundary": CORPUS["persistence"], "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({"schema": "V23P03C18BrandImpactManifestV1", "artifact": "V23P03C18BrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "P04_BRAND_CLOSURE_SURFACE_DECLARED_NO_SHIPPING_UI", "affectedSurfacePaths": [], "semanticStates": ["PREVIEW", "PROMOTED", "ROLLED_BACK", "FORWARD_FIX_REQUIRED", "FAILED_CLOSED"], "contractArtifact": contract_row, "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def _manifest_row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if relative in rendered:
        raw = rendered[relative]
        return {"path": relative, "state": "GENERATED", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    path = root / relative
    if path.is_file():
        raw = path.read_bytes()
        return {"path": relative, "state": "WORKTREE", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    if relative in EXISTING_PATHS:
        raw = _git_blob(root, relative)
        return {"path": relative, "state": "BASE_HEAD", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    return {"path": relative, "state": "MISSING_NEW_PATH", "bytes": 0, "sha256": sha256_bytes(b"")}


def all_outputs(root: Path) -> dict[str, bytes]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract_raw = pretty(contract_document(root, schema_row))
    contract_row = json.loads(contract_raw.decode("utf-8"))
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract_row))
    brand_raw = pretty(brand_document(contract_row))
    rendered: dict[str, bytes] = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({"schema": "V23P03C18ToolingManifestV1", "artifact": "V23P03C18ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE), "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "artifacts": manifest_rows, "artifactSetDigest": sha256_value(manifest_rows), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "persistenceBoundary": CORPUS["persistence"], "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered

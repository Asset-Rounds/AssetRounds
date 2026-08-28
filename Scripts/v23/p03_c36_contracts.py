#!/usr/bin/env python3
"""Deterministic static contract corpus and evidence builders for V23-P03-C36.

Card C36 is the field-draft resilience slice.  This module is deliberately
static-only: it records the hydrated authority, the complete path fence, the
typed draft/attachment/saga contract, and a synthetic conformance corpus.  It
does not read customer data, create a second store or writer, or claim native,
hosted, adoption, acceptance, or release evidence.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C36"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 53
BASE_HEAD = "17333e529253a2a2f39c2a13bb41b30e0ff6c384"
BASE_TREE = "afc6da08e44ed5ac640d5e0962b71bdcb7f8fc2b"
CONTEXT_DIGEST = "4daf6b1a4556c4db876efdce8c9f0681a5e257d7fd352dde6413bdf86b67b6bf"
FENCE_DIGEST = "205df5643f4f73344eb052a36a8271500eceeb131bef4fdb1084f6efc56aa629"
PREREQUISITE_DIGEST = "87dc175b2112b6bc38e38e5999cba77128905d5d5d9fd5272749b2d45475dfd8"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
COORDINATION_HEAD = "180fb91d6e1da6db0330d8145cbdb2c4ba9276d"
COORDINATION_TREE = "36ab340456e94ca38495505e0b480a7a33f3cc39"
COORDINATION_LEDGER_DIGEST = "2eba51e9e12422da9da425bb968c5b92bfb0651b86bac0f26ddb68774de0b437"
COORDINATION_PROJECTION_DIGEST = "66e52dff7c5484e5cb4cad911232c966aa4e22b3343e4c9a8fee254361a2edf6"
COORDINATION_CAS_SEQUENCE = 225
HYDRATION_TRANSITION_DIGEST = "e0a4cf56d3d511e24074285cfc6174d0a045513f20de73a0fd28e92ec365567b"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "c45aebce4d9f8a8201feafc7b1e3e38f5b8f31843b8fbdb1cc73767f6d2c8b21"
DOSSIER_SHA256 = "a452f00325779c4a1709f1387a88b26e86b256dba8b2d7c312c715dd8cfb80d1"
DOSSIER_UTF8_LENGTH = 7179
INHERITED_V21_BLOCK_SHA256 = "fabcc91bbb6cdefc4b8ff0d894cbc42e110bb54bd6667c391e7b614d50886cce"
INHERITED_V21_BLOCK_UTF8_LENGTH = 18906

SCHEMA_PATH = "Scripts/v23/field-draft-resilience.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C36FieldDraftResilienceContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C36FieldDraftResilienceEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C36BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C36-tooling-manifest.json"

SCRIPT_PATHS = (
    "Scripts/v23/p03_c36_contracts.py",
    "Scripts/v23/generate_p03_c36_contracts.py",
    "Scripts/v23/verify_p03_c36_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

# These are the exact 87 BASE_HEAD source paths in the applied C36 fence.
EXISTING_PATHS = (
    "FieldEvidenceApp/Resources/Localizable.xcstrings",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/DeviceLifecycleCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift",
    "FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift",
    "FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/LocalJobStoreSchemaV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/LocalJobStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/JobScaleBudgetPolicyV1.swift",
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
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceAppTests/S3_1DraftSchemaTests.swift",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests.swift",
    "FieldEvidenceAppTests/S3_4ResumeRecoveryTests.swift",
    "FieldEvidenceAppTests/S3_5FailureIntegrityTests.swift",
    "FieldEvidenceAppTests/S3_6CameraRecoveryTests.swift",
    "FieldEvidenceAppTests/S6_1DeletionGraphTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S7_4DraftAccessPolicyTests.swift",
    "FieldEvidenceAppTests/S7_5DataRightsIntegrationTests.swift",
    "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_09ConcurrencyScaleTests.swift",
    "FieldEvidenceAppTests/V9_10LifecycleBoundaryTests.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
)

# The 18 new paths are hydrated C36 ownership plus this static tooling lane.
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Drafts/DraftRecoveryProjectionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftAutosaveSchedulerV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftAttachmentStagingAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftCommitSagaRecoveryV1.swift",
    "FieldEvidenceAppTests/V9_30FieldDraftResilienceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Drafts/V21P03C36FieldDraftResilienceCorpusV1.json",
    *TOOL_PATHS,
)

PATH_FENCE = EXISTING_PATHS + NEW_PATHS
FULL_FENCE_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
SOURCE_REFERENCE_PATHS = EXISTING_PATHS
AUTHORITY_REFERENCE_PATHS = (
    "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md",
)

# Compact proof rows preserve the exact applied edge total without copying all
# 665 path-level overlap edges into every generated artifact.
PRIOR_FENCE_OVERLAPS = (
    {"cardID": "V23-P00-C10", "fenceDigest": "f34d2e3ea8defd5ff7146a499b88e39c76b0a925c519bb524120a2542064d1cb", "disposition": "CHECK_RUNNER_COMMAND_AND_FINALIZATION_GUARD_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P00-C11", "fenceDigest": "560b3bd0401d0da46bcedc9f7184c8041e198db8cbe8af3011731fc0ad6cc8b1", "disposition": "ERASE_CONCURRENCY_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P01-C01", "fenceDigest": "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", "disposition": "SCHEMA_SUCCESSOR_AND_MIGRATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C02", "fenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", "disposition": "OWNED_FILE_RESTORE_CLONE_FORK_AND_GENERATION_REPROOF_REQUIRED", "overlapCount": 8},
    {"cardID": "V23-P01-C03", "fenceDigest": "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", "disposition": "COPY_ON_WRITE_MIGRATION_RECOVERY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P01-C04", "fenceDigest": "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", "disposition": "ARCHIVE_AND_OPEN_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C05", "fenceDigest": "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", "disposition": "CANONICAL_BACKUP_RESTORE_AND_IDENTITY_REPROOF_REQUIRED", "overlapCount": 12},
    {"cardID": "V23-P01-C06", "fenceDigest": "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", "disposition": "DELETE_ERASE_AND_PORTABLE_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 24},
    {"cardID": "V23-P01-C07", "fenceDigest": "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", "disposition": "RELEASED_DATA_AND_HISTORIC_REPORT_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 7},
    {"cardID": "V23-P02-C01", "fenceDigest": "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", "disposition": "SOLE_WRITER_AND_COMMAND_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P02-C02", "fenceDigest": "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", "disposition": "MUTATION_RECEIPT_JOURNAL_AND_RECOVERY_REPROOF_REQUIRED", "overlapCount": 30},
    {"cardID": "V23-P02-C03", "fenceDigest": "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", "disposition": "SYNC_CLASSIFICATION_AND_CONFLICT_REPROOF_REQUIRED", "overlapCount": 23},
    {"cardID": "V23-P02-C04", "fenceDigest": "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", "disposition": "GENERATION_LEASE_AND_STALE_WRITER_REPROOF_REQUIRED", "overlapCount": 9},
    {"cardID": "V23-P02-C05", "fenceDigest": "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", "disposition": "RESUMABLE_JOB_BOUNDARY_REPROOF_REQUIRED", "overlapCount": 14},
    {"cardID": "V23-P02-C06", "fenceDigest": "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", "disposition": "DEVICE_TIME_AND_PROTECTED_DATA_REPROOF_REQUIRED", "overlapCount": 11},
    {"cardID": "V23-P02-C07", "fenceDigest": "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", "disposition": "OBSERVATION_TIME_AND_PROJECTION_REPROOF_REQUIRED", "overlapCount": 23},
    {"cardID": "V23-P02-C08", "fenceDigest": "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", "disposition": "SYSTEM_HEALTH_CLASSIFICATION_REPROOF_REQUIRED", "overlapCount": 8},
    {"cardID": "V23-P02-C09", "fenceDigest": "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", "disposition": "PERSISTENT_KIND_LIFECYCLE_COVERAGE_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P03-C05", "fenceDigest": "f6ef2e304901fc4ccc103c5c210eee65b26faefb6b96a2cd8ae3a171debab614", "disposition": "CONTENT_REFERENCE_WRITER_INTEGRITY_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 4},
    {"cardID": "V23-P03-C07", "fenceDigest": "3f6a36f8794c159c24c26ec06506bff77a2d998df3cf04a5b8b06bb1d56e8264", "disposition": "KERNEL_BACKUP_RESTORE_DELETE_ERASE_REGISTRY_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P03-C08", "fenceDigest": "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", "disposition": "PACK_LIFECYCLE_BACKUP_RESTORE_AND_DELETE_REPROOF_REQUIRED", "overlapCount": 11},
    {"cardID": "V23-P03-C09", "fenceDigest": "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", "disposition": "SEARCH_SCHEMA_REBUILD_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 36},
    {"cardID": "V23-P03-C10", "fenceDigest": "7e90b5eb871c6560b395fb487d0155a31a499009c6a2d4303b0aa668476d80f8", "disposition": "PORTABLE_KERNEL_CONFORMANCE_HARNESS_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P03-C11", "fenceDigest": "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", "disposition": "JOURNAL_CHECKPOINT_AND_REPLAY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C12", "fenceDigest": "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "disposition": "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED", "overlapCount": 28},
    {"cardID": "V23-P03-C13", "fenceDigest": "3a8af6eccec4a8842fde87c41ba665400ec2d20a8c80796c9945559b6c4c49ef", "disposition": "DIRECT_PREREQUISITE_EVIDENCE_ASSURANCE_REPROOF_REQUIRED", "overlapCount": 55},
    {"cardID": "V23-P03-C14", "fenceDigest": "ba02fb62b37fcf10416c474cfaa366d5a2ec8f6785ca10a581fd940b6643a2d3", "disposition": "ORDERED_PREDECESSOR_SHARED_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 57},
    {"cardID": "V23-P03-C15", "fenceDigest": "a0b746c04bf9016ca5dd421ac95973065a066e6f53a30c347c94c747f9607308", "disposition": "ORDERED_PREDECESSOR_WORK_PACKET_AND_SHARED_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 57},
    {"cardID": "V23-P03-C16", "fenceDigest": "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "disposition": "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C35", "fenceDigest": "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "disposition": "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED", "overlapCount": 32},
    {"cardID": "V23-P03-C38", "fenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", "disposition": "ACCOUNTABILITY_ACTOR_QUALIFICATION_SNAPSHOT_REPROOF_REQUIRED", "overlapCount": 37},
    {"cardID": "V23-P03-C39", "fenceDigest": "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2", "disposition": "ASSET_SEMANTICS_SUBJECT_PACKAGE_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 37},
    {"cardID": "V23-P03-C40", "fenceDigest": "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397", "disposition": "DIRECT_PREREQUISITE_AUTHORITY_AND_SHARED_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 46},
    {"cardID": "V23-P03-C41", "fenceDigest": "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000", "disposition": "DIRECT_PREREQUISITE_FUNCTIONAL_SNAPSHOT_REPROOF_REQUIRED", "overlapCount": 55},
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 53,
    "priorOwnedPathCount": 883,
    "overlapCount": 665,
    "authorizedOverlapCount": 665,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = (
    "DraftPurposeRegistryV1",
    "DraftScopeKeyV1",
    "DraftPayloadCodecReleaseV1",
    "FieldDraftCheckpointV1",
    "DraftAutosavePolicyV1",
    "DraftDurabilityPresentationStateV1",
    "DraftResumeAnchorV1",
    "AttachmentStagingItemV1",
    "AttachmentStagingStateV1",
    "DraftCommitPlanV1",
    "DraftCommitSagaV1",
    "DraftContentReservationV1",
    "DraftCommitReceiptV1",
    "DraftConflictResolutionPlanV1",
    "DraftDiscardPlanV1",
    "DraftDiscardReceiptV1",
    "DraftRecoveryProjectionV1",
    "DraftLifecycleDispositionV1",
)

PERSISTENT_MODEL_FAMILIES = (
    {"familyID": "FIELD_DRAFT_CHECKPOINT", "model": "FieldDraftCheckpointRow", "contract": "FieldDraftCheckpointV1"},
    {"familyID": "ATTACHMENT_STAGING_ITEM", "model": "AttachmentStagingItemRow", "contract": "AttachmentStagingItemV1"},
    {"familyID": "DRAFT_COMMIT_SAGA", "model": "DraftCommitSagaRow", "contract": "DraftCommitSagaV1"},
    {"familyID": "DRAFT_CONTENT_RESERVATION", "model": "DraftContentReservationRow", "contract": "DraftContentReservationV1"},
    {"familyID": "DRAFT_COMMIT_RECEIPT", "model": "DraftCommitReceiptRow", "contract": "DraftCommitReceiptV1"},
    {"familyID": "DRAFT_DISCARD_RECEIPT", "model": "DraftDiscardReceiptRow", "contract": "DraftDiscardReceiptV1"},
)
PERSISTENT_MODEL_COUNT = 64
PREDECESSOR_MODEL_COUNT = 58
ADDED_PERSISTENT_MODEL_COUNT = len(PERSISTENT_MODEL_FAMILIES)
PERSISTENT_FAMILY_COUNT = len(PERSISTENT_MODEL_FAMILIES)

LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V16_VERSIONED_IDENTITY",
    "WRITER_COMMAND_QUERY",
    "MIGRATION_AND_RECOVERY",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK_GENERATION",
    "IMPORT_EXPORT_PREVIEW",
    "JOURNAL_REPLAY_CHECKPOINT",
    "DELETE_ERASE_RETENTION",
    "LOCAL_SEARCH_REBUILD",
    "REPORT_SNAPSHOT_OPEN_JSON",
    "PRIVACY_PROGRESSIVE_DISCLOSURE",
    "LOCALIZATION_ACCESSIBILITY",
    "INTERRUPTION_IDEMPOTENT_RECEIPTS",
    "CONTENT_RESERVATION_RECONCILIATION",
    "DRAFT_PURPOSE_CODEC_BUDGETS",
)
FORBIDDEN_CLAIMS = (
    "CLOUD_UPLOAD_SYNC_ACCOUNT_STATE",
    "SECOND_WRITER_CONTENT_STORE_OR_SCRATCH_ROOT",
    "RECOVERY_CENTER_OR_BACKGROUND_DAEMON",
    "REQUIRED_SAVE_BUTTON_OR_OPTIMISTIC_DURABILITY",
    "GENERIC_FORM_STORE_OR_SILENT_STALE_MERGE",
    "AUTOMATIC_COMMIT_FINALIZE_PROMOTION_OR_DISCARD",
    "CROSS_FILESYSTEM_OR_SWIFTDATA_ATOMICITY",
    "DRAFT_DATA_IN_EVIDENCE_REPORT_EXPORT_SEARCH_OR_METRICS",
    "CASCADE_DELETE_IDENTITY_MERGE_OR_PUBLIC_COMPLETION",
    "S10_RELEASE_OR_BRAND_APPROVAL",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV9_FieldDraftResilienceG01PurposeCheckpointAutosaveAndPresentationTruth",
    "testV9_FieldDraftResilienceA01AttachmentStagingAndPerItemFailureRemainLocal",
    "testV9_FieldDraftResilienceH01CASWorkspaceCodecReservationAndRetentionFailClosed",
    "testV9_FieldDraftResilienceI01CommitSagaInterruptionAndIdempotentRecovery",
    "testV9_FieldDraftResilienceR01BackupRestoreCloneForkDeleteEraseReplayAndExclusion",
)
SOURCE_CONTRACT_TOKENS = (CARD, "V21-P03-C36", *CONTRACT_NAMES)

SOURCE_PROJECTION = {
    "registerRows": [
        "| 53 | <a id=\"v23-p03-c36-register\"></a>[`V23-P03-C36`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c36) | Universal field-draft checkpoints, durable attachment staging, interruption recovery, and truthful local-save state | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C14`, `V23-P03-C15` | `EXACT_WITH_GENERATION_REBIND` |",
    ],
    "registerSectionSHA256": REGISTER_SECTION_SHA256,
    "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256,
    "dossierSHA256": DOSSIER_SHA256,
    "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
    "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True,
    "facetRowCount": 1,
    "canonicalRecordWriterOwnershipRowCount": 9,
    "facetManifestDigest": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C36).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C36", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
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

SEMANTIC_SCOPE = {
    "durableOwner": ["FieldDraftCheckpointV1", "AttachmentStagingItemV1", "DraftCommitSagaV1", "DraftContentReservationV1", "DraftCommitReceiptV1", "DraftDiscardReceiptV1", "PersistentSchemaV16"],
    "purposePolicy": "CLOSED_TYPED_PURPOSE_CODEC_SCOPE_BUDGET_TARGET_RETENTION_ATTACHMENT_PRIVACY_AND_LIFECYCLE_REGISTRY_WITH_NO_GENERIC_JSON_EAV_STORE",
    "autosavePolicy": "INJECTED_CLOCK_TRAILING_750_MS_MAXIMUM_DIRTY_5_SECONDS_AND_FORCED_FLUSH_BOUNDARIES_WITH_RECEIPT_READ_BACK_TRUTH",
    "stagingPolicy": "PER_ITEM_DURABLE_LOCAL_STAGING_AFTER_DISPOSABLE_SCRATCH_WITH_NO_EVIDENCE_COMPLETION_REPORT_SEARCH_EXPORT_METRIC_OR_PUBLIC_TRUTH",
    "commitPolicy": "CONTENT_PROMOTION_THEN_EXISTING_SOLE_WORKSPACE_WRITER_TARGET_RECEIPT_READ_BACK_THEN_IDEMPOTENT_DRAFT_RETIREMENT_WITH_NO_CROSS_FILESYSTEM_ATOMICITY_CLAIM",
    "conflictPolicy": "EXACT_DRAFT_AND_BASE_REVISION_CAS_WITH_EXPLICIT_REVIEW_AND_REBASE_COMMIT_AS_COPY_CONTINUE_EDITING_OR_DISCARD_RECEIPT",
    "fullLifecyclePolicy": "V16_SCHEMA_RECORDS15_ZERO_INVENTION_MIGRATION_BACKUP_RESTORE_CLONE_FORK_DELETE_ERASE_JOURNAL_REPLAY_RETENTION_LOCALIZATION_ACCESSIBILITY_INTERRUPTION_AND_FORWARD_FIX_ENROLLED_BEFORE_FIRST_WRITE",
    "forbiddenPolicy": "NO_CLOUD_ACCOUNT_SYNC_SECOND_WRITER_STORE_CONTENT_ROOT_RECOVERY_CENTER_BACKGROUND_DAEMON_REQUIRED_SAVE_OPTIMISTIC_DURABILITY_AUTOMATIC_COMMIT_SILENT_MERGE_OR_DISCARD",
    "s10Policy": "EXACT_ONE_HUNDRED_FIVE_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP_AND_VISIBLE_TODAY_WORK_UI_DEFERRED",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
    "persistentModelFamilyCount": PERSISTENT_FAMILY_COUNT,
    "persistentModelCount": PERSISTENT_MODEL_COUNT,
}

REQUIRED_BEHAVIORS = (
    "CLOSED_PURPOSE_CODEC_REGISTRY_AND_TYPED_SCOPE_BUDGETS",
    "CHECKPOINT_EXPECTED_DRAFT_AND_BASE_REVISION_CAS",
    "TRAILING_750_MS_AND_MAXIMUM_FIVE_SECOND_DIRTY_INTERVAL",
    "FORCED_FLUSH_BEFORE_BACKGROUND_HANDOFF_PROMOTION_AND_EXPORT",
    "PER_ITEM_DURABLE_ATTACHMENT_STAGING_AND_FAILURE_ISOLATION",
    "CONTENT_PROMOTION_BEFORE_SOLE_WRITER_EFFECT",
    "EFFECT_BEFORE_RECEIPT_AND_IDEMPOTENT_COMMIT_SAGA_RECOVERY",
    "NO_CROSS_FILESYSTEM_ATOMICITY_OR_SECOND_FINAL_AUTHORITY",
    "EXPLICIT_CONFLICT_REBASE_COPY_CONTINUE_OR_DISCARD_RECEIPTS",
    "RESERVATION_RETENTION_UNTIL_NO_LIVE_REFERENCE",
    "QUIESCENT_BACKUP_WITH_RESTORE_CLONE_FORK_DELETE_AND_ERASE_BINDINGS",
    "DRAFTS_EXCLUDED_FROM_REPORT_EXPORT_SEARCH_SPOTLIGHT_SUPPORT_AND_METRICS",
    "REBUILDABLE_SAFE_RESUME_PROJECTION_WITHOUT_DRAFT_TEXT",
    "V16_RECORDS15_AND_64_MODEL_SIX_FAMILY_ENROLLMENT_BEFORE_FIRST_WRITE",
)

EVIDENCE_CASES = (
    {"evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "focus": ["purpose_registry", "checkpoint_revision", "autosave_deadline", "presentation_read_back"], "expected": "typed_checkpoint_and_receipt_truth"},
    {"evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "focus": ["photo_audio_video_file", "per_item_failure", "protected_data", "low_storage"], "expected": "sibling_staging_is_preserved_and_safe_resume_is_local"},
    {"evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "focus": ["unknown_codec", "stale_cas", "wrong_workspace", "forged_digest", "live_reservation_retention"], "expected": "fail_closed_without_partial_canonical_success"},
    {"evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "focus": ["checkpoint", "content_promotion", "target_effect_receipt", "canonical_read_back", "draft_retirement"], "expected": "same_saga_receipt_or_no_effect_after_relaunch"},
    {"evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "focus": ["backup_restore", "clone_fork_remap", "journal_replay", "orphan_reconciliation", "delete_erase"], "expected": "byte_and_history_preserving_rebuild"},
)

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
        {
            "cardID": "V23-P03-C14", "attemptID": 1,
            "candidateHead": "cf425681d53f5ca5f05b06895ea0badb5b340aee",
            "candidateTree": "7db980a30ce3ec4ca6af86b9f70b2e41a811355c",
            "contextDigest": "7f6260c6cb9de92f31e0afb694b5e746eca46aeea01153ede4568a76ae6b9bea",
            "pathFenceDigest": "ba02fb62b37fcf10416c474cfaa366d5a2ec8f6785ca10a581fd940b6643a2d3",
            "verificationReceiptDigest": "3580261b758762beb84dca7e2c93157ac33e0d024eb7af5b501335025c55d24c",
            "checkpointDigest": "cf41c116c9026d72e067501a5e265c013c879f181b28b4251656a04431dcf8e4",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C14_HEAD",
        },
        {
            "cardID": "V23-P03-C15", "attemptID": 1,
            "candidateHead": BASE_HEAD, "candidateTree": BASE_TREE,
            "contextDigest": "8e0f76262c67db671706d6c7a17c46b404bb7a2470af8424321a8503045fc632",
            "pathFenceDigest": "a0b746c04bf9016ca5dd421ac95973065a066e6f53a30c347c94c747f9607308",
            "verificationReceiptDigest": "f1f0301e50ee65ce2a6f02fd6d4881d7c6d6d9f664fbf5100f55652bb3c2ea4a",
            "checkpointDigest": "ce4faafb0703c72eb0ff88a27044f9491f133f3f7a177e6c2fc223b5b690e5e0",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C15_HEAD",
        },
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

CORPUS: dict[str, Any] = {
    "schema": "V21P03C36FieldDraftResilienceCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "requiredContractNames": list(CONTRACT_NAMES),
    "persistentModelFamilies": [dict(value) for value in PERSISTENT_MODEL_FAMILIES],
    "persistentModelFamilyCount": PERSISTENT_FAMILY_COUNT,
    "persistentModelCount": PERSISTENT_MODEL_COUNT,
    "lifecycleDimensions": list(LIFECYCLE_DIMENSIONS),
    "persistence": {
        "schemaRelease": "PERSISTENT_SCHEMA_V16_FIELD_DRAFT_RESILIENCE",
        "recordSchemaVersion": 15,
        "predecessorSchemaVersion": 15,
        "predecessorRecordSchemaVersion": 14,
        "migration": "EXACT_V15_TO_V16_COPY_ON_WRITE",
        "canonicalWriter": "V23-P02-C01",
        "lifecycleOwner": CARD,
        "firstWriteEnrolled": True,
        "compatibilityRequired": True,
        "backupRestoreRequired": True,
        "deleteEraseRequired": True,
        "exportImportPreviewRequired": False,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V16_WRITE",
        "persistentFamilies": [dict(value) for value in PERSISTENT_MODEL_FAMILIES],
        "predecessorModelCount": PREDECESSOR_MODEL_COUNT,
        "addedPersistentModelCount": ADDED_PERSISTENT_MODEL_COUNT,
        "persistentModelCount": PERSISTENT_MODEL_COUNT,
        "persistentModelFamilyCount": PERSISTENT_FAMILY_COUNT,
        "persistedContractFamilies": [value["contract"] for value in PERSISTENT_MODEL_FAMILIES],
        "nonPersistentFamilies": ["DraftRecoveryProjectionV1", "DraftDurabilityPresentationStateV1"],
        "currentProjectionRows": 0,
        "currentProjectionRowCount": 0,
        "recordsSchemaVersion": 15,
        "secondWriter": False,
        "secondStore": False,
        "crossFilesystemAtomicityClaim": False,
        "c35ReadOnly": True,
    },
    "autosave": {
        "trailingNanoseconds": 750_000_000,
        "maximumDirtyNanoseconds": 5_000_000_000,
        "forceFlushBoundaries": ["NAVIGATION", "BACKGROUND", "HANDOFF", "PROMOTION", "SHARE"],
    },
    "limits": {
        "maximumPayloadBytes": 2_097_152,
        "maximumStageItems": 128,
        "maximumScopeComponents": 16,
        "maximumAnchorComponents": 12,
        "maximumTextBytes": 512,
    },
    "purposes": [
        {"purpose": "INSPECTION_REVIEW", "codecID": "c36.inspection_review", "codecVersion": 1, "maximumPayloadBytes": 4096, "maximumStageItems": 4, "targetCommand": "apply_inspection_review", "retention": "EXPLICIT_DISCARD_ONLY", "privacy": "WORKSPACE_PRIVATE", "attachmentKinds": ["AUDIO", "FILE", "PHOTO", "VIDEO"]},
        {"purpose": "WORK_PACKET", "codecID": "c36.work_packet", "codecVersion": 1, "maximumPayloadBytes": 4096, "maximumStageItems": 4, "targetCommand": "apply_work_packet", "retention": "EXPLICIT_DISCARD_ONLY", "privacy": "WORKSPACE_PRIVATE", "attachmentKinds": ["AUDIO", "FILE", "PHOTO", "VIDEO"]},
        {"purpose": "CORRECTIVE_ACTION", "codecID": "c36.corrective_action", "codecVersion": 1, "maximumPayloadBytes": 4096, "maximumStageItems": 4, "targetCommand": "finalize_correction", "retention": "EXPLICIT_DISCARD_ONLY", "privacy": "WORKSPACE_PRIVATE", "attachmentKinds": ["AUDIO", "FILE", "PHOTO", "VIDEO"]},
        {"purpose": "REQUIREMENT_EVALUATION", "codecID": "c36.requirement_evaluation", "codecVersion": 1, "maximumPayloadBytes": 4096, "maximumStageItems": 4, "targetCommand": "apply_requirement_assurance", "retention": "EXPLICIT_DISCARD_ONLY", "privacy": "WORKSPACE_PRIVATE", "attachmentKinds": ["AUDIO", "FILE", "PHOTO", "VIDEO"]},
        {"purpose": "EVIDENCE_CURATION", "codecID": "c36.evidence_curation", "codecVersion": 1, "maximumPayloadBytes": 4096, "maximumStageItems": 4, "targetCommand": "apply_evidence_assurance", "retention": "EXPLICIT_DISCARD_ONLY", "privacy": "RESTRICTED_EVIDENCE", "attachmentKinds": ["AUDIO", "FILE", "PHOTO", "VIDEO"]},
        {"purpose": "ASSET_FIELD_EDIT", "codecID": "c36.asset_field_edit", "codecVersion": 1, "maximumPayloadBytes": 4096, "maximumStageItems": 4, "targetCommand": "apply_asset_semantics", "retention": "RETIRE_AFTER_COMMIT", "privacy": "WORKSPACE_PRIVATE", "attachmentKinds": ["AUDIO", "FILE", "PHOTO", "VIDEO"]},
    ],
    "checkpointStates": ["ACTIVE", "COMMITTING", "CONFLICTED", "RECOVERY_REQUIRED", "COMMITTED", "DISCARD_PENDING", "DISCARDED"],
    "presentationStates": ["UNSAVED_CHANGES", "SAVING_ON_THIS_IPHONE", "SAVED_ON_THIS_IPHONE", "SAVE_BLOCKED", "COMMITTING", "CONFLICTED", "RECOVERY_REQUIRED", "COMMITTED", "DISCARDING", "DISCARDED"],
    "attachmentPresentationStates": ["SELECTED", "LOADING", "STAGED_LOCAL", "PROCESSING", "READY", "RETRYABLE_FAILURE", "BLOCKED", "REMOVED", "PROMOTED"],
    "attachmentStates": ["CAPTURING", "HASHING", "PROCESSING", "READY_LOCAL", "FAILED_RETRYABLE", "FAILED_FINAL", "REMOVE_PENDING", "COMMITTED", "ORPHAN_QUARANTINED"],
    "sagaStates": ["PREPARED", "CONTENT_PROMOTED_UNBOUND", "TARGET_COMMITTED", "DRAFT_RETIRE_PENDING", "DRAFT_RETIRED", "CONFLICTED", "RECOVERY_REQUIRED"],
    "sagaEdges": [
        ["PREPARED", "CONTENT_PROMOTED_UNBOUND"], ["CONTENT_PROMOTED_UNBOUND", "TARGET_COMMITTED"], ["TARGET_COMMITTED", "DRAFT_RETIRE_PENDING"], ["DRAFT_RETIRE_PENDING", "DRAFT_RETIRED"],
        ["PREPARED", "CONFLICTED"], ["PREPARED", "RECOVERY_REQUIRED"], ["CONTENT_PROMOTED_UNBOUND", "CONFLICTED"], ["CONTENT_PROMOTED_UNBOUND", "RECOVERY_REQUIRED"],
        ["TARGET_COMMITTED", "RECOVERY_REQUIRED"], ["DRAFT_RETIRE_PENDING", "RECOVERY_REQUIRED"], ["CONFLICTED", "RECOVERY_REQUIRED"], ["CONFLICTED", "PREPARED"],
        ["RECOVERY_REQUIRED", "PREPARED"], ["RECOVERY_REQUIRED", "CONTENT_PROMOTED_UNBOUND"], ["RECOVERY_REQUIRED", "TARGET_COMMITTED"], ["RECOVERY_REQUIRED", "DRAFT_RETIRE_PENDING"],
    ],
    "conflictPlans": ["REVIEW_AND_REBASE", "COMMIT_AS_COPY", "CONTINUE_EDITING", "DISCARD"],
    "reservationStates": ["RESERVED", "REUSED", "ASSOCIATED", "ORPHAN_QUARANTINED", "DELETED"],
    "recoveryStatuses": ["RESUMABLE", "CONFLICT", "MISSING_MEDIA", "LOW_STORAGE", "PROTECTED_DATA", "UNSUPPORTED_CODEC", "PARTIAL_STAGE", "STALE_TARGET", "RECOVERY_REQUIRED"],
    "safeActions": ["RESUME_REVIEW", "REVIEW_CONFLICT", "RETRY_ITEM", "FREE_STORAGE", "UNLOCK_DEVICE", "DISCARD", "OPEN_SAFE_PARENT"],
    "lifecycleDispositions": ["PERSISTENT_WORKSPACE_OPERATIONAL", "SAFE_RESUME_DERIVED_ONLY", "EXCLUDED_FROM_CANONICAL_TRUTH"],
    "backupRestore": {
        "fieldDraftKinds": ["CHECKPOINT", "STAGING_ITEM", "COMMIT_SAGA", "CONTENT_RESERVATION", "COMMIT_RECEIPT", "DISCARD_RECEIPT"],
        "restoresCheckpoint": True, "restoresReadyLocal": True, "restoresReservations": True,
        "restoresPromotedUnbound": True, "restoresStableSagaEdge": True,
        "cloneDisposition": "RESTORE_REQUIRES_USER_REVIEW", "configurationCloneDisposition": "EXCLUDED_FROM_CONFIGURATION_CLONE",
    },
    "privacyExclusions": ["EVIDENCE", "REPORT", "EXPORT", "SEARCH", "SPOTLIGHT", "SUPPORT", "INTEGRATION_EVENT", "METRICS"],
    "coverage": {
        "casDraftAndBaseRevision": True, "perItemFailureIsolation": True, "exactRetryReusesReservation": True,
        "noSecondWriter": True, "noSecondStore": True, "noCloudStore": True, "recordsAreCanonicalOnlyAfterCommit": True,
    },
    "singleAuthority": {
        "writerProtocol": "FieldDraftWritingV1", "coordinator": "FieldDraftCoordinatorV1",
        "recoveryProjection": "DraftRecoveryProjectionCoordinatorV1", "persistentRows": 6,
        "secondWriter": False, "secondStore": False,
    },
    "boundaryRefs": list(EVIDENCE_IDS),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    "evidenceCases": list(EVIDENCE_CASES),
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
    rows: list[dict[str, Any]] = []
    for relative in SOURCE_REFERENCE_PATHS:
        raw = _git_blob(root, relative)
        rows.append({"path": relative, "source": "BASE_HEAD_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return rows


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for relative in AUTHORITY_REFERENCE_PATHS:
        raw = _git_blob(root, relative)
        rows.append({"path": relative, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return rows


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
        return {"type": "string", "minLength": 1}
    if isinstance(value, list):
        result: dict[str, Any] = {"type": "array", "minItems": len(value), "maxItems": len(value)}
        variants: dict[bytes, dict[str, Any]] = {}
        for item in value:
            item_schema = _schema_for_value(item)
            variants[canonical(item_schema)] = item_schema
        if variants:
            result["items"] = next(iter(variants.values())) if len(variants) == 1 else {"anyOf": [variants[key] for key in sorted(variants)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(f"unsupported schema value: {type(value)!r}")


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/schemas/v23/field-draft-resilience.schema.json", "title": "V23-P03-C36 field-draft resilience corpus"})
    return document


def _flags() -> dict[str, bool]:
    return {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False, "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False}


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationTransitionSequence": COORDINATION_CAS_SEQUENCE, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C14", "V23-P03-C15"],
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "PERSISTENT_SCHEMA_V16_FIELD_DRAFT_RESILIENCE",
        "recordSchemaVersion": 15, "persistentModelCount": PERSISTENT_MODEL_COUNT, "persistentModelFamilyCount": PERSISTENT_FAMILY_COUNT,
        "schemaBehaviorDelta": True, "migrationBehaviorDelta": True, "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": False,
        "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True, "deleteCompatibilityRequired": True, "exportCompatibilityRequired": False,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V16_WRITE", "uiSurfaceDelta": False, "brandSurfaceDelta": False,
        "nativeCompileRan": False, "hostedDispatchEnabled": False, "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False, "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True, "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "pathFenceDigest": FENCE_DIGEST, "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "s10FenceOverlapPaths": []}


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"blueprintPath": AUTHORITY_REFERENCE_PATHS[0], "foundationPath": AUTHORITY_REFERENCE_PATHS[1], "sourceProjection": SOURCE_PROJECTION, "sourceTokens": list(SOURCE_CONTRACT_TOKENS), "requiredContractNames": list(CONTRACT_NAMES), "lineage": "EXACT_WITH_GENERATION_REBIND", "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows}


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    return _sealed({
        "schema": "V23P03C36FieldDraftResilienceContractV1", "artifact": "V23P03C36FieldDraftResilienceContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "schemaArtifact": schema_row, "sourceContract": _source_contract(source_rows, authority_rows),
        "semanticScope": SEMANTIC_SCOPE, "requiredSemantics": {"contractNames": list(CONTRACT_NAMES), "persistentModelFamilies": [dict(value) for value in PERSISTENT_MODEL_FAMILIES], "persistentModelCount": PERSISTENT_MODEL_COUNT, "persistentModelFamilyCount": PERSISTENT_FAMILY_COUNT, "checkpointStates": CORPUS["checkpointStates"], "presentationStates": CORPUS["presentationStates"], "attachmentStates": CORPUS["attachmentStates"], "sagaStates": CORPUS["sagaStates"], "conflictPlans": CORPUS["conflictPlans"], "recoveryStatuses": CORPUS["recoveryStatuses"], "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": list(FORBIDDEN_CLAIMS)},
        "persistenceBoundary": CORPUS["persistence"], "requiredLifecycle": list(LIFECYCLE_DIMENSIONS), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES),
        "successor": {"cardID": "V23-P03-C17", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {"contractNames": list(CONTRACT_NAMES), "persistentModelFamilies": [dict(value) for value in PERSISTENT_MODEL_FAMILIES], "checkpointStates": CORPUS["checkpointStates"], "presentationStates": CORPUS["presentationStates"], "attachmentStates": CORPUS["attachmentStates"], "sagaStates": CORPUS["sagaStates"], "conflictPlans": CORPUS["conflictPlans"], "recoveryStatuses": CORPUS["recoveryStatuses"], "requiredBehaviors": list(REQUIRED_BEHAVIORS), "requiredLifecycle": list(LIFECYCLE_DIMENSIONS)}
    return _sealed({
        "schema": "V23P03C36FieldDraftResilienceEvidenceReceiptV1", "artifact": "V23P03C36FieldDraftResilienceEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows),
        "schemaArtifact": schema_row, "contractArtifact": {"path": CONTRACT_PATH, "bytes": len(pretty(contract_row)), "sha256": sha256_bytes(pretty(contract_row))}, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics),
        "persistenceBoundary": CORPUS["persistence"], "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C36BrandImpactManifestV1", "artifact": "V23P03C36BrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI",
        "affectedSurfacePaths": [], "semanticStates": CORPUS["presentationStates"] + CORPUS["attachmentStates"], "contractArtifact": contract_row,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


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
    manifest = _sealed({
        "schema": "V23P03C36ToolingManifestV1", "artifact": "V23P03C36ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "artifacts": manifest_rows,
        "artifactSetDigest": sha256_value(manifest_rows), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "persistenceBoundary": CORPUS["persistence"], "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered

#!/usr/bin/env python3
"""Deterministic static contract and evidence builders for V23-P03-C14."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C14"
TITLE = "InspectionReviewStateV1, explicit change requests, and complete CorrectiveActionPolicyV1 semantics"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 51
BASE_HEAD = "4235b8e844153eadcf463ce640e2af8a40838da7"
BASE_TREE = "13cf5166983893fddf6988ffcbada28decde63f7"
CONTEXT_DIGEST = "7f6260c6cb9de92f31e0afb694b5e746eca46aeea01153ede4568a76ae6b9bea"
FENCE_DIGEST = "ba02fb62b37fcf10416c474cfaa366d5a2ec8f6785ca10a581fd940b6643a2d3"
PREREQUISITE_DIGEST = "dbc357083a890d70dc6eea630d99a5d98b0b7518925677260fd8f363411e4cf7"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
COORDINATION_HEAD = "a145b4b2eb999ae0381cac450799161aaf758131"
COORDINATION_TREE = "7ed9704eacb805130138034595ab8406542a9cd0"
COORDINATION_LEDGER_DIGEST = "2dadb7626963d5396b841e5336f5b608d8dd1c0814362b4cdecfa0b79355c4ca"
COORDINATION_CAS_SEQUENCE = 216
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "774c2cb1c6b41b51c55bb50f0ccc2bb95fd3fe83706997990238485754359b76"
DOSSIER_SHA256 = "25b696fa8be1e8c9c3fcb9f6cd470b48c4ed79145c74f11607faa94ff8a73547"
DOSSIER_UTF8_LENGTH = 7122
INHERITED_V21_BLOCK_SHA256 = "68cadfad62ced190ec6d6cdaad5f29935cc914a56f77de208ba78bb6e6f66306"
INHERITED_V21_BLOCK_UTF8_LENGTH = 9118

SCHEMA_PATH = "Scripts/v23/review-corrective-action.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C14ReviewAndCorrectiveActionContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C14ReviewAndCorrectiveActionEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C14BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C14-tooling-manifest.json"
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/ReviewAndCorrectiveAction/V21P03C14ReviewAndCorrectiveActionCorpusV1.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c14_contracts.py",
    "Scripts/v23/generate_p03_c14_contracts.py",
    "Scripts/v23/verify_p03_c14_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

EXISTING_PATHS = (
    "FieldEvidenceApp/Resources/Localizable.xcstrings",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_19LocalSearchTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/S6_1DeletionGraphTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
    "FieldEvidenceApp/Domain/Reporting/EvidenceAssuranceContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/EvidenceAssurancePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Reporting/EvidenceAssuranceCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/EvidenceAssuranceLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/FunctionalRelationships/FunctionalRelationshipContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/FunctionalRelationshipPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/FunctionalRelationships/FunctionalRelationshipCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/FunctionalRelationships/FunctionalRelationshipLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/AuthorityCriterionContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/FindingContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationEngineV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/FindingLifecycleV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CorrectiveWorkContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/VerifiedRecheckContractsV1.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportCorrectionRule.swift",
    "FieldEvidenceAppTests/V9_23PartyAccountabilityTests.swift",
    "FieldEvidenceAppTests/V9_25AuthorityCriterionDerivationTests.swift",
    "FieldEvidenceAppTests/V9_26FunctionalRelationshipTests.swift",
    "FieldEvidenceAppTests/V9_27EvidenceAssuranceTests.swift",
    "FieldEvidenceAppTests/V9_14FindingLifecycleTests.swift",
    "FieldEvidenceAppTests/S5_4RecheckCNVTests.swift",
    "FieldEvidenceAppTests/S5_2RecheckOutcomeTests.swift",
    "FieldEvidenceAppTests/S3_3FinalizationTests.swift",
    "FieldEvidenceAppTests/S4_5CorrectionTests.swift",
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/InspectionKernel/InspectionReviewContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/ReviewAndCorrectiveActionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Review/InspectionReviewCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Review/InspectionReviewLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_28InspectionReviewCorrectiveActionTests.swift",
    FIXTURE_PATH,
    *SCRIPT_PATHS,
    SCHEMA_PATH,
    CONTRACT_PATH,
    EVIDENCE_PATH,
    BRAND_PATH,
    MANIFEST_PATH,
)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
FULL_FENCE_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
SOURCE_REFERENCE_PATHS = EXISTING_PATHS
AUTHORITY_REFERENCE_PATHS = (
    "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md",
)

PRIOR_FENCE_OVERLAPS = (
    {"cardID": "V23-P00-C10", "fenceDigest": "f34d2e3ea8defd5ff7146a499b88e39c76b0a925c519bb524120a2542064d1cb", "disposition": "CHECK_RUNNER_COMMAND_AND_FINALIZATION_GUARD_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P00-C11", "fenceDigest": "560b3bd0401d0da46bcedc9f7184c8041e198db8cbe8af3011731fc0ad6cc8b1", "disposition": "ERASE_CONCURRENCY_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P01-C01", "fenceDigest": "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", "disposition": "SCHEMA_SUCCESSOR_AND_MIGRATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C02", "fenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", "disposition": "OWNED_FILE_RESTORE_CLONE_FORK_AND_GENERATION_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P01-C03", "fenceDigest": "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", "disposition": "COPY_ON_WRITE_MIGRATION_RECOVERY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P01-C04", "fenceDigest": "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", "disposition": "ARCHIVE_AND_OPEN_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C05", "fenceDigest": "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", "disposition": "CANONICAL_BACKUP_RESTORE_AND_IDENTITY_REPROOF_REQUIRED", "overlapCount": 12},
    {"cardID": "V23-P01-C06", "fenceDigest": "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", "disposition": "DELETE_ERASE_AND_PORTABLE_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 23},
    {"cardID": "V23-P01-C07", "fenceDigest": "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", "disposition": "RELEASED_DATA_AND_HISTORIC_REPORT_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 7},
    {"cardID": "V23-P02-C01", "fenceDigest": "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", "disposition": "SOLE_WRITER_AND_COMMAND_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P02-C02", "fenceDigest": "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", "disposition": "MUTATION_RECEIPT_JOURNAL_AND_RECOVERY_REPROOF_REQUIRED", "overlapCount": 29},
    {"cardID": "V23-P02-C03", "fenceDigest": "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", "disposition": "SYNC_CLASSIFICATION_AND_CONFLICT_REPROOF_REQUIRED", "overlapCount": 21},
    {"cardID": "V23-P02-C04", "fenceDigest": "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", "disposition": "GENERATION_LEASE_AND_STALE_WRITER_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P02-C05", "fenceDigest": "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", "disposition": "RESUMABLE_JOB_BOUNDARY_REPROOF_REQUIRED", "overlapCount": 9},
    {"cardID": "V23-P02-C06", "fenceDigest": "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", "disposition": "DEVICE_TIME_AND_PROTECTED_DATA_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P02-C07", "fenceDigest": "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", "disposition": "OBSERVATION_TIME_AND_PROJECTION_REPROOF_REQUIRED", "overlapCount": 27},
    {"cardID": "V23-P02-C08", "fenceDigest": "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", "disposition": "SYSTEM_HEALTH_CLASSIFICATION_REPROOF_REQUIRED", "overlapCount": 4},
    {"cardID": "V23-P02-C09", "fenceDigest": "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", "disposition": "PERSISTENT_KIND_LIFECYCLE_COVERAGE_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C04", "fenceDigest": "cafb01052cd0eb74fb7a90f0815439d3e3b29811c3a8b920fbae4d948d5c166c", "disposition": "FINDING_CLAIM_EVIDENCE_BOUNDARY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C06", "fenceDigest": "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2", "disposition": "COMPLETED_SNAPSHOT_IMMUTABILITY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P03-C07", "fenceDigest": "3f6a36f8794c159c24c26ec06506bff77a2d998df3cf04a5b8b06bb1d56e8264", "disposition": "KERNEL_BACKUP_RESTORE_DELETE_ERASE_REGISTRY_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P03-C08", "fenceDigest": "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", "disposition": "PACK_LIFECYCLE_BACKUP_RESTORE_AND_DELETE_REPROOF_REQUIRED", "overlapCount": 11},
    {"cardID": "V23-P03-C09", "fenceDigest": "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", "disposition": "SEARCH_SCHEMA_REBUILD_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 39},
    {"cardID": "V23-P03-C10", "fenceDigest": "7e90b5eb871c6560b395fb487d0155a31a499009c6a2d4303b0aa668476d80f8", "disposition": "PORTABLE_KERNEL_CONFORMANCE_HARNESS_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P03-C11", "fenceDigest": "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", "disposition": "JOURNAL_CHECKPOINT_AND_REPLAY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C12", "fenceDigest": "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "disposition": "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED", "overlapCount": 34},
    {"cardID": "V23-P03-C13", "fenceDigest": "3a8af6eccec4a8842fde87c41ba665400ec2d20a8c80796c9945559b6c4c49ef", "disposition": "DIRECT_PREREQUISITE_EVIDENCE_ASSURANCE_REPROOF_REQUIRED", "overlapCount": 79},
    {"cardID": "V23-P03-C16", "fenceDigest": "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "disposition": "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C35", "fenceDigest": "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "disposition": "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED", "overlapCount": 37},
    {"cardID": "V23-P03-C38", "fenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", "disposition": "ACCOUNTABILITY_ACTOR_QUALIFICATION_SNAPSHOT_REPROOF_REQUIRED", "overlapCount": 50},
    {"cardID": "V23-P03-C39", "fenceDigest": "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2", "disposition": "ASSET_SEMANTICS_SUBJECT_PACKAGE_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 48},
    {"cardID": "V23-P03-C40", "fenceDigest": "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397", "disposition": "DIRECT_PREREQUISITE_AUTHORITY_AND_SHARED_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 66},
    {"cardID": "V23-P03-C41", "fenceDigest": "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000", "disposition": "DIRECT_PREREQUISITE_FUNCTIONAL_SNAPSHOT_REPROOF_REQUIRED", "overlapCount": 74},
)
PRIOR_FENCE_PROOF = {"fenceCount": 51, "priorOwnedPathCount": 851, "overlapCount": 634, "authorizedOverlapCount": 634, "unauthorizedOverlapCount": 0, "overlapCards": list(PRIOR_FENCE_OVERLAPS)}

CONTRACT_NAMES = (
    "InspectionReviewStateV1",
    "ReviewDispositionV1",
    "ChangeRequestV1",
    "CorrectiveActionPolicyV1",
    "ImmutableReviewAndCorrectiveActionHistoriesV1",
)
SUBJECT_KINDS = ("COMPLETED_ACTIVITY_SNAPSHOT", "REPORT_SNAPSHOT", "FINDING")
REVIEW_STATES = ("DRAFT", "FIELD_COMPLETE", "READY_FOR_REVIEW", "CHANGES_REQUESTED", "ACCEPTED", "FINALIZED", "AMENDED", "SUPERSEDED")
DISPOSITION_KINDS = ("CHANGES_REQUESTED", "ACCEPTED")
CHANGE_ITEM_KINDS = ("REVIEW", "FINDING", "CRITERION", "EVIDENCE", "FUNCTIONAL_RELATIONSHIP")
CHANGE_REQUEST_STATES = ("OPEN", "RESOLVED", "WITHDRAWN", "SUPERSEDED")
EVIDENCE_KINDS = ("CLAIM_EVIDENCE_LINK", "VERIFIED_RECHECK", "COMPLETED_ACTIVITY_SNAPSHOT", "REQUIREMENT_EVALUATION", "FUNCTIONAL_RELATIONSHIP_SNAPSHOT", "EXTERNAL_EVIDENCE_REFERENCE")
ACTION_PRIORITIES = ("URGENT", "HIGH", "NORMAL", "LOW")
ACTION_STATES = ("OPEN", "IN_PROGRESS", "AWAITING_VERIFICATION", "CLOSED", "REOPENED", "SUPERSEDED")
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V14_RECORDS13_VERSIONED_IDENTITY",
    "WRITER_COMMAND_QUERY_EXPECTED_REVISION_MUTATION_ID",
    "V13_TO_V14_COPY_ON_WRITE_MIGRATION",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK_GENERATION",
    "IMPORT_EXPORT_METADATA_ONLY_PREVIEW",
    "JOURNAL_REPLAY_CHECKPOINT",
    "DELETE_ERASE_RETENTION",
    "LOCAL_SEARCH_REBUILD",
    "REPORT_SNAPSHOT_OPEN_JSON",
    "LOCALIZATION_ACCESSIBILITY_PRIVACY",
    "INTERRUPTION_IDEMPOTENT_RECEIPTS",
    "DOWNGRADE_FORWARD_FIX_AFTER_FIRST_V14_WRITE",
)
FORBIDDEN_CLAIMS = (
    "ACCOUNT_OR_AUTHENTICATED_IDENTITY", "CLOUD_PROVIDER_OR_REMOTE_STORAGE", "DELIVERY_OR_TRANSMISSION_OUTBOX",
    "CMMS_WORK_ORDER_OR_INVENTORY", "AI_DIAGNOSIS_OR_AUTOMATIC_PASS_FAIL", "LEGAL_SIGNATURE_OR_NONREPUDIATION",
    "SECURITY_CERTIFICATION_OR_VERIFIED_IDENTITY", "FINALIZATION_OR_RELEASE_APPROVAL_PRODUCER",
    "NATIVE_IPAD_OR_SECOND_UI_SURFACE", "CUSTOMER_DATA_TELEMETRY_OR_MARKETING", "SECOND_STORE_OR_SECOND_CANONICAL_WRITER",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV9_InspectionReviewG01StateMachineDispositionAndClosureMatrix",
    "testV9_InspectionReviewA01PriorityDueGraceAndLocalActorAlternates",
    "testV9_InspectionReviewH01StaleRevisionMissingEvidenceAndForbiddenScopeFailClosed",
    "testV9_InspectionReviewI01InterruptedMigrationMutationProjectionAndReplayRecover",
    "testV9_InspectionReviewR01BackupRestoreCloneForkDeleteEraseSearchReportAndHistoryPreserve",
)
SOURCE_CONTRACT_TOKENS = (CARD, "V21-P03-C14", "InspectionReviewStateV1", "ReviewDispositionV1", "ChangeRequestV1", "CorrectiveActionPolicyV1")

TEST_CORPUS_SHAPE = {
    "cardID": CARD,
    "ordinal": REGISTER_ORDINAL,
    "phase": "P03",
    "reviewStates": list(REVIEW_STATES),
    "correctiveActionStates": list(ACTION_STATES),
    "declaredReviewTransitions": [
        {"from": "DRAFT", "to": "FIELD_COMPLETE", "requiresExactSuccessorSubject": False},
        {"from": "FIELD_COMPLETE", "to": "READY_FOR_REVIEW", "requiresExactSuccessorSubject": False},
        {"from": "READY_FOR_REVIEW", "to": "CHANGES_REQUESTED", "requiresExactSuccessorSubject": False},
        {"from": "CHANGES_REQUESTED", "to": "READY_FOR_REVIEW", "requiresExactSuccessorSubject": False},
        {"from": "READY_FOR_REVIEW", "to": "ACCEPTED", "requiresExactSuccessorSubject": False},
        {"from": "ACCEPTED", "to": "FINALIZED", "requiresExactSuccessorSubject": False},
        {"from": "FINALIZED", "to": "AMENDED", "requiresExactSuccessorSubject": False},
        {"from": "DRAFT", "to": "SUPERSEDED", "requiresExactSuccessorSubject": True},
        {"from": "FIELD_COMPLETE", "to": "SUPERSEDED", "requiresExactSuccessorSubject": True},
        {"from": "READY_FOR_REVIEW", "to": "SUPERSEDED", "requiresExactSuccessorSubject": True},
        {"from": "CHANGES_REQUESTED", "to": "SUPERSEDED", "requiresExactSuccessorSubject": True},
        {"from": "ACCEPTED", "to": "SUPERSEDED", "requiresExactSuccessorSubject": True},
        {"from": "FINALIZED", "to": "SUPERSEDED", "requiresExactSuccessorSubject": True},
        {"from": "AMENDED", "to": "SUPERSEDED", "requiresExactSuccessorSubject": True},
    ],
    "declaredCorrectiveActionTransitions": [
        {"from": "OPEN", "to": "IN_PROGRESS"},
        {"from": "OPEN", "to": "AWAITING_VERIFICATION"},
        {"from": "IN_PROGRESS", "to": "AWAITING_VERIFICATION"},
        {"from": "AWAITING_VERIFICATION", "to": "IN_PROGRESS"},
        {"from": "AWAITING_VERIFICATION", "to": "CLOSED"},
        {"from": "CLOSED", "to": "REOPENED"},
        {"from": "REOPENED", "to": "IN_PROGRESS"},
        {"from": "REOPENED", "to": "AWAITING_VERIFICATION"},
        {"from": "OPEN", "to": "SUPERSEDED"},
        {"from": "IN_PROGRESS", "to": "SUPERSEDED"},
        {"from": "AWAITING_VERIFICATION", "to": "SUPERSEDED"},
        {"from": "CLOSED", "to": "SUPERSEDED"},
        {"from": "REOPENED", "to": "SUPERSEDED"},
    ],
    "boundaryRefs": ["V23-P03-C13", "V23-P03-C38", "V23-P03-C40", "V23-P03-C41"],
    "coverage": ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"],
    "evidenceIDs": ["G01", "A01", "H01", "I01", "R01"],
    "persistentModelCount": 53,
    "recordsSchemaVersion": 13,
    "provisionalFlags": {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False},
}

SEMANTIC_SCOPE = {
    "durableOwner": [*CONTRACT_NAMES, "PersistentSchemaV14"],
    "reviewPolicy": "GUARDED_DRAFT_FIELD_COMPLETE_READY_CHANGES_REQUESTED_ACCEPTED_FINALIZED_AMENDED_AND_SUPERSEDED_TRANSITIONS_WITH_NO_IN_PLACE_ACCEPTED_EDIT",
    "changeRequestPolicy": "IMMUTABLE_ITEM_SCOPE_REASON_REQUESTED_CHANGE_EVIDENCE_ACTOR_EXACT_REVISION_RESOLUTION_AND_HISTORY",
    "correctivePolicy": "VERSIONED_PRIORITY_DUE_GRACE_LOCAL_ASSIGNMENT_REFERENCE_CLOSURE_EVIDENCE_INDEPENDENT_VERIFIER_REOPEN_AND_SUPERSESSION",
    "actorPolicy": "LOCAL_ACTOR_AND_ASSIGNEE_REFERENCE_ONLY_WITH_NO_ACCOUNT_AUTHORIZATION_OR_VERIFIED_IDENTITY_CLAIM",
    "writerPolicy": "SOLE_WORKSPACE_WRITER_EXPECTED_REVISION_MUTATION_ID_ATOMIC_BUNDLE_DURABLE_RECEIPT_JOURNAL_AND_RECOVERY",
    "fullLifecyclePolicy": "V14_SCHEMA_RECORDS13_MIGRATION_BACKUP_RESTORE_CLONE_FORK_DELETE_ERASE_EXPORT_REPORT_SEARCH_JOURNAL_REPLAY_LOCALIZATION_ACCESSIBILITY_PRIVACY_AND_INTERRUPTION_ENROLLED_BEFORE_FIRST_WRITE",
    "forbiddenPolicy": "NO_ACCOUNTS_AUTH_CLOUD_PROVIDER_DELIVERY_CMMS_AI_COMPLIANCE_LEGAL_NONREPUDIATION_SIGNING_UPLOAD_SUBMISSION_OR_FINALIZATION_PRODUCER",
    "s10Policy": "EXACT_EIGHTY_SIX_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}
REQUIRED_BEHAVIORS = (
    {"id": "C14-S01", "contract": "InspectionReviewStateV1", "requirement": "Guarded append-only review transitions reject undeclared jumps and in-place accepted edits.", "evidence": "V23-P03-C14-G01"},
    {"id": "C14-S02", "contract": "ReviewDispositionV1", "requirement": "Dispositions bind exact subject/revision and preserve immutable local reviewer history.", "evidence": "V23-P03-C14-G01"},
    {"id": "C14-S03", "contract": "ChangeRequestV1", "requirement": "Requests freeze item scope, reason, requested change/evidence, actor, revision, resolution, and lineage.", "evidence": "V23-P03-C14-A01"},
    {"id": "C14-S04", "contract": "CorrectiveActionPolicyV1", "requirement": "Priority, due, grace, assignment, closure evidence, verifier, reopen, and supersession are typed/versioned.", "evidence": "V23-P03-C14-G01"},
    {"id": "C14-S05", "contract": "ImmutableReviewAndCorrectiveActionHistoriesV1", "requirement": "Ordered histories are append-only and projections are deterministic rebuild-only.", "evidence": "V23-P03-C14-R01"},
    {"id": "C14-L01", "contract": "PersistentSchemaV14", "requirement": "Records schema 13 uses exact V13-to-V14 copy-on-write migration with compatibility/recovery.", "evidence": "V23-P03-C14-I01"},
    {"id": "C14-L02", "contract": CARD, "requirement": "Backup/restore, clone/fork, import/export, journal/replay, search, report, delete/Erase, localization, accessibility, privacy, downgrade, and interruption are explicit before first write.", "evidence": "V23-P03-C14-R01"},
    {"id": "C14-B01", "contract": CARD, "requirement": "Static provisional tooling makes no native, hosted, adoption, acceptance, release, or credit claim.", "evidence": "V23-P03-C14-H01"},
)
EVIDENCE_CASES = (
    {"id": "V23-P03-C14-G01", "kind": "REVIEW_STATE_AND_CORRECTIVE_ACTION_MATRIX", "assertion": "Synthetic review states, dispositions, requests, corrective priorities, due/grace, closure, verifier, reopen, and supersession cover the golden path."},
    {"id": "V23-P03-C14-A01", "kind": "LOCAL_POLICY_ALTERNATES", "assertion": "No-due, elapsed, calendar-local, assignment, and verifier alternatives remain version-bound and local-only."},
    {"id": "V23-P03-C14-H01", "kind": "HOSTILE_BOUNDARY", "assertion": "Cross-workspace, undeclared transition, stale revision, duplicate/rewrite, missing closure evidence, wrong verifier, prohibited producer, and persisted current-row attempts fail closed."},
    {"id": "V23-P03-C14-I01", "kind": "INTERRUPTION_BOUNDARY", "assertion": "Migration, writer bundle, transition, projection, backup/restore, delete/Erase, and replay interruption retains prior authority or one complete effect/receipt."},
    {"id": "V23-P03-C14-R01", "kind": "RECOVERY_BOUNDARY", "assertion": "Backup/restore, clone/fork, forward-fix, journal replay, search rebuild, report open JSON, delete/Erase, and immutable history recovery reproduce typed state."},
)

SOURCE_PROJECTION = {
    "registerRows": ["| 51 | <a id=\x22v23-p03-c14-register\x22></a>[\x60V23-P03-C14\x60](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c14) | InspectionReviewStateV1, explicit change requests, and complete CorrectiveActionPolicyV1 semantics | \x60IMPLEMENT_NOW\x60 | \x60NOT_STARTED\x60 | \x60V23-P03-C13\x60, \x60V23-P03-C41\x60 | \x60REFINED_WITHOUT_LOSS\x60 |"],
    "registerSectionSHA256": REGISTER_SECTION_SHA256, "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256, "dossierSHA256": DOSSIER_SHA256, "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True, "facetRowCount": 1, "canonicalRecordWriterOwnershipRowCount": 9,
    "facetManifestDigest": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C14).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"], "deterministicEvidenceIDs": list(EVIDENCE_IDS), "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"], "invalidationConsumers": ["V23-P03-C36", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
    "optionalCapabilityProviders": ["NONE"], "reservedLegacyOwnerReconciliationDebtCount": 0, "reservedLegacyOwnerReconciliationDebtPaths": [],
    "reservedLegacyRawWriteViolationCount": 0, "reservedLegacyRawWriteViolationPaths": [], "provisionalZeroViolationClosureClaimed": False,
    "canonicalRegisterDigest": "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd",
    "directGraphDigest": "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae",
    "selectorManifestDigest": "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2",
    "relationManifestDigest": "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4",
    "dependencyDispositionDigest": "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c",
    "impactManifestDigest": "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b",
}
DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1", "schemaVersion": 1, "successorCardID": CARD, "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 2, "canonicalRelationPreserved": True, "nonreleaseSpecialEdgeApplied": False,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY", "nativeCompileRan": False,
    "physicalLockedState": "REQUIRED_PENDING_OWNER", "acceptanceCredit": False, "releaseCredit": False, "createdAt": "2026-08-28T02:30:00Z",
    "predecessors": [
        {"cardID": "V23-P03-C13", "attemptID": 1, "candidateHead": "4235b8e844153eadcf463ce640e2af8a40838da7", "candidateTree": "13cf5166983893fddf6988ffcbada28decde63f7", "contextDigest": "2f00ad4af54e789e795d14a64af7b0f66d6c54169043e7585a32e5dd645e7141", "pathFenceDigest": "3a8af6eccec4a8842fde87c41ba665400ec2d20a8c80796c9945559b6c4c49ef", "verificationReceiptDigest": "149248b1319a772e8ff224728e58b1fbcb02040655e2fa25826f40d80bc61901", "checkpointDigest": "bd25e41b4a2328bfad8380dc78ab75f0c1ff0b3afac411f44280aaba7602f630", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C13_HEAD"},
        {"cardID": "V23-P03-C41", "attemptID": 1, "candidateHead": "458a19d2ed16826ec93b1ce688ffa4e1e8e57b59", "candidateTree": "74c59c691c72c3d37c08b0c9a5d318d635844a82", "contextDigest": "2a812d74def7b09e4339a99919fcaed0ac7f96ab750622fceb0c0e2280845364", "pathFenceDigest": "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000", "verificationReceiptDigest": "b0004d88627fc107d0fc9555765abae7ea211149407c9e0f0aacda105efe0768", "checkpointDigest": "3f9876516881e4a79cc5ce7065c4f397093a93b17c8a7fac5916adae183553fc", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C41_HEAD"},
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}
ORDERING_AUTHORITY = {"cardID": "V23-P03-C41", "attemptID": 1, "candidateHead": "458a19d2ed16826ec93b1ce688ffa4e1e8e57b59", "candidateTree": "74c59c691c72c3d37c08b0c9a5d318d635844a82", "contextDigest": "2a812d74def7b09e4339a99919fcaed0ac7f96ab750622fceb0c0e2280845364", "pathFenceDigest": "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000", "checkpointDigest": "3f9876516881e4a79cc5ce7065c4f397093a93b17c8a7fac5916adae183553fc", "disposition": "CHECKPOINTED_PROVISIONAL_ORDERING_AUTHORITY_AT_EXACT_C41_HEAD"}
PERSISTENCE = {
    "schemaRelease": "PERSISTENT_SCHEMA_V14_REVIEW_AND_CORRECTIVE_ACTION", "recordSchemaVersion": 13, "predecessorSchemaVersion": 13,
    "predecessorRecordSchemaVersion": 12, "migration": "EXACT_V13_TO_V14_COPY_ON_WRITE", "canonicalWriter": "V23-P02-C01", "lifecycleOwner": CARD,
    "firstWriteEnrolled": True, "compatibilityRequired": True, "backupRestoreRequired": True, "deleteEraseRequired": True, "exportImportPreviewRequired": True,
    "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V14_WRITE", "persistedFamilies": list(CONTRACT_NAMES), "durableRowCount": 5,
    "currentProjectionRows": 0, "currentProjectionRowCount": 0, "recordsSchemaVersion": 13, "secondStore": False, "secondWriter": False,
    "accountStore": False, "cloudStore": False, "deliveryOutbox": False, "descriptorEventOnlyPersistence": False,
    "nonPersistentFamilies": ["InspectionReviewProjectionV1", "CorrectiveActionProjectionV1", "ReviewDispositionPreviewV1"],
    "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY", "snapshotBinding": "COMPLETED_ACTIVITY_OR_REPORT_SNAPSHOT_EXACT_SUBJECT_DIGEST_REQUIRED",
    "purposeBinding": "REVIEW_SUBJECT_AND_LOCAL_ACTOR_SCOPE_REQUIRED", "supersessionAndVoid": "APPEND_ONLY_IMMUTABLE_HISTORY", "legacyRowsCreated": 0,
}

def _transition(identifier: str, revision: int, source: str, destination: str, reason: str) -> dict[str, Any]:
    return {"id": identifier, "reviewID": "review-synthetic-1", "workspaceID": "workspace-synthetic-1", "revision": revision, "fromState": source, "toState": destination, "reason": reason, "recorded": True, "immutable": True}


CORPUS: dict[str, Any] = {
    "schema": "V21P03C14ReviewAndCorrectiveActionCorpusV1", "schemaVersion": 1, "cardID": CARD, "synthetic": True, "containsCustomerData": False, "containsSecrets": False,
    "requiredContractNames": list(CONTRACT_NAMES), "subjectKinds": list(SUBJECT_KINDS), "reviewStates": list(REVIEW_STATES), "dispositionKinds": list(DISPOSITION_KINDS),
    "changeItemKinds": list(CHANGE_ITEM_KINDS), "changeRequestStates": list(("OPEN", "RESOLVED", "WITHDRAWN", "SUPERSEDED")), "evidenceKinds": list(EVIDENCE_KINDS),
    "actionPriorities": list(ACTION_PRIORITIES), "actionStates": list(ACTION_STATES), "persistence": PERSISTENCE,
    "reviewTransitions": [
        _transition("transition-draft-field-complete", 1, "DRAFT", "FIELD_COMPLETE", "field data complete"),
        _transition("transition-field-complete-ready", 2, "FIELD_COMPLETE", "READY_FOR_REVIEW", "ready for local review"),
        _transition("transition-ready-changes", 3, "READY_FOR_REVIEW", "CHANGES_REQUESTED", "additional evidence requested"),
        _transition("transition-changes-ready", 4, "CHANGES_REQUESTED", "READY_FOR_REVIEW", "requested changes resolved"),
        _transition("transition-ready-accepted", 5, "READY_FOR_REVIEW", "ACCEPTED", "review accepted"),
        _transition("transition-accepted-finalized", 6, "ACCEPTED", "FINALIZED", "finalized local review"),
        _transition("transition-finalized-amended", 7, "FINALIZED", "AMENDED", "subject amended"),
        _transition("transition-amended-superseded", 8, "AMENDED", "SUPERSEDED", "exact successor subject recorded"),
    ],
    "reviewDispositions": [
        {"id": "disposition-changes-1", "reviewID": "review-synthetic-1", "kind": "CHANGES_REQUESTED", "reviewRevision": 3, "changeRequestIDs": ["change-request-1"], "localOnly": True, "immutable": True},
        {"id": "disposition-accepted-1", "reviewID": "review-synthetic-1", "kind": "ACCEPTED", "reviewRevision": 5, "changeRequestIDs": [], "localOnly": True, "immutable": True},
    ],
    "changeRequests": [
        {"id": "change-request-1", "reviewID": "review-synthetic-1", "itemKind": "EVIDENCE", "itemID": "evidence-synthetic-1", "itemRevision": 1, "itemSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "reason": "attach closure evidence", "requestedChange": "record exact evidence digest", "requestedEvidence": ["CLAIM_EVIDENCE_LINK"], "actorID": "actor-synthetic-1", "revision": 1, "state": "OPEN", "immutable": True},
        {"id": "change-request-1-resolved", "reviewID": "review-synthetic-1", "itemKind": "EVIDENCE", "itemID": "evidence-synthetic-1", "itemRevision": 1, "itemSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "reason": "attach closure evidence", "requestedChange": "record exact evidence digest", "requestedEvidence": ["CLAIM_EVIDENCE_LINK"], "actorID": "actor-synthetic-1", "revision": 2, "state": "RESOLVED", "resolution": "FULFILLED", "resolutionEvidence": ["CLAIM_EVIDENCE_LINK"], "immutable": True},
    ],
    "correctiveActionPolicies": [{
        "id": "policy-synthetic-v1", "releaseID": "policy-release-synthetic-v1", "workspaceID": "workspace-synthetic-1", "revision": 1,
        "priorityRules": [{"priority": "URGENT", "dueRule": "ELAPSED_SECONDS", "amount": 3600, "graceSeconds": 600}, {"priority": "HIGH", "dueRule": "CALENDAR_DAYS_AT_LOCAL_TIME", "amount": 1, "localHour": 17, "localMinute": 0, "graceSeconds": 3600}, {"priority": "NORMAL", "dueRule": "CALENDAR_DAYS_AT_LOCAL_TIME", "amount": 7, "localHour": 17, "localMinute": 0, "graceSeconds": 86400}, {"priority": "LOW", "dueRule": "NO_DUE_DATE", "amount": None, "graceSeconds": 0}],
        "assignmentRule": "REQUIRED", "closureEvidenceRequirements": [{"requirementID": "closure-recheck", "kind": "VERIFIED_RECHECK", "minimumCount": 1}],
        "verifierRule": "DIFFERENT_ACTOR_REFERENCE_REQUIRED", "reopenTriggers": ["FAILED_VERIFIED_RECHECK", "NEW_EVIDENCE_DIGEST", "SUBJECT_AMENDED", "MANUAL_RECORDED_REASON"], "immutable": True,
    }],
    "correctiveActionEvents": [
        {"id": "action-open-1", "actionID": "action-synthetic-1", "revision": 1, "state": "OPEN", "priority": "HIGH", "assignee": "actor-assignee-1", "closureEvidence": [], "verifier": None, "immutable": True},
        {"id": "action-progress-1", "actionID": "action-synthetic-1", "revision": 2, "state": "IN_PROGRESS", "priority": "HIGH", "assignee": "actor-assignee-1", "closureEvidence": [], "verifier": None, "immutable": True},
        {"id": "action-awaiting-verification-1", "actionID": "action-synthetic-1", "revision": 3, "state": "AWAITING_VERIFICATION", "priority": "HIGH", "assignee": "actor-assignee-1", "closureEvidence": ["VERIFIED_RECHECK"], "verifier": None, "immutable": True},
        {"id": "action-closed-1", "actionID": "action-synthetic-1", "revision": 4, "state": "CLOSED", "priority": "HIGH", "assignee": "actor-assignee-1", "closureEvidence": ["VERIFIED_RECHECK"], "verifier": "actor-verifier-1", "immutable": True},
        {"id": "action-reopened-1", "actionID": "action-synthetic-1", "revision": 5, "state": "REOPENED", "priority": "HIGH", "assignee": "actor-assignee-1", "closureEvidence": [], "verifier": None, "reopenTrigger": "FAILED_VERIFIED_RECHECK", "immutable": True},
        {"id": "action-superseded-1", "actionID": "action-synthetic-1", "revision": 6, "state": "SUPERSEDED", "priority": "HIGH", "assignee": None, "closureEvidence": [], "verifier": None, "immutable": True},
    ],
    "immutableHistories": [{"id": "review-history-1", "kind": "REVIEW", "headRevision": 8, "eventCount": 8, "appendOnly": True, "rewriteAllowed": False, "immutable": True}, {"id": "action-history-1", "kind": "CORRECTIVE_ACTION", "headRevision": 6, "eventCount": 6, "appendOnly": True, "rewriteAllowed": False, "immutable": True}],
    "currentProjectionRows": [], "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY",
    "projectionRebuild": {"reviewProjectionRows": 0, "correctiveActionProjectionRows": 0, "dispositionPreviewRows": 0, "deterministic": True, "rebuildFromOrderedHistory": True},
    "dispositionPreviews": [{"id": "preview-request-changes", "operation": "REQUEST_CHANGES", "writes": 0, "disposition": "PREVIEW_ONLY", "historyPreserved": True}, {"id": "preview-close-action", "operation": "CLOSE_CORRECTIVE_ACTION", "writes": 0, "disposition": "REVIEW_REQUIRED", "historyPreserved": True}, {"id": "preview-reopen-action", "operation": "REOPEN_CORRECTIVE_ACTION", "writes": 0, "disposition": "REVIEW_REQUIRED", "historyPreserved": True}],
    "completedSnapshots": [{"id": "snapshot-synthetic-1", "workspaceID": "workspace-synthetic-1", "subjectID": "completed-activity-snapshot-1", "subjectRevision": 1, "subjectSHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "frozen": True, "rewriteOnLaterChange": False}],
    "lifecycleCoverage": [{"dimension": dimension, "enrolledBeforeFirstWrite": True, "disposition": "EXPLICIT_STATIC_CONTRACT"} for dimension in LIFECYCLE_DIMENSIONS],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED"} for case_id in ("cross-workspace-subject", "cross-workspace-actor", "undeclared-transition", "accepted-in-place-edit", "stale-review-revision", "stale-action-revision", "duplicate-history-revision", "history-rewrite", "missing-change-request-reason", "missing-closure-evidence", "required-assignee-missing", "wrong-verifier", "unknown-reopen-trigger", "supersession-without-successor", "current-projection-row", "second-store", "second-writer", "account-producer", "cloud-producer", "delivery-outbox", "cmms-work-order", "ai-diagnosis", "legal-signature", "nonrepudiation", "finalization-producer", "customer-telemetry")],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "PRIOR_ACCEPTED_REVISION_OR_NO_PARTIAL_AUTHORITY"} for case_id in ("migration-boundary", "writer-bundle", "review-transition", "disposition-write", "change-request-write", "policy-admission", "corrective-event", "projection-rebuild", "backup-export", "restore-replace", "delete-erase", "journal-replay", "search-rebuild", "report-open-json")],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "RECOVER_EFFECT_RECEIPT_AND_HISTORY"} for case_id in ("backup-restore", "clone-fork", "compatibility-forward-fix", "journal-replay", "checkpoint-replay", "search-rebuild", "report-snapshot", "delete-erase", "released-v14", "immutable-history")],
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
    if value is None: return {"type": "null"}
    if isinstance(value, bool): return {"type": "boolean"}
    if isinstance(value, int): return {"type": "integer"}
    if isinstance(value, float): return {"type": "number"}
    if isinstance(value, str): return {"type": "string"}
    if isinstance(value, list):
        result: dict[str, Any] = {"type": "array", "minItems": len(value), "maxItems": len(value)}
        schemas = {_schema_for_value(item).__repr__(): _schema_for_value(item) for item in value}
        if schemas: result["items"] = next(iter(schemas.values())) if len(schemas) == 1 else {"anyOf": [schemas[key] for key in sorted(schemas)]}
        if all(isinstance(item, str) for item in value): result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(type(value))


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/review-corrective-action.schema.json", "title": "V23 P03 C14 Review and Corrective Action Corpus"})
    return document


def _flags() -> dict[str, bool]:
    return {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False, "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False}


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE, "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C13", "V23-P03-C41"], "orderingAuthorityCards": ["V23-P03-C41"],
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": PERSISTENCE["schemaRelease"], "recordSchemaVersion": 13, "recordsSchemaVersion": 13, "durableRowCount": 5, "currentProjectionRowCount": 0, "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY",
        "schemaBehaviorDelta": True, "migrationBehaviorDelta": True, "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True, "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True, "downgradeDisposition": PERSISTENCE["downgrade"],
        "uiSurfaceDelta": False, "brandSurfaceDelta": False, "nativeCompileRan": False, "hostedDispatchEnabled": False, "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False, "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True, "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "pathFenceDigest": FENCE_DIGEST, "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "s10FenceOverlapPaths": [], "manifestInputCount": len(MANIFEST_INPUT_PATHS), "toolPaths": list(TOOL_PATHS)}


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"blueprintPath": AUTHORITY_REFERENCE_PATHS[0], "foundationPath": AUTHORITY_REFERENCE_PATHS[1], "sourceProjection": SOURCE_PROJECTION, "sourceTokens": list(SOURCE_CONTRACT_TOKENS), "requiredContractNames": list(CONTRACT_NAMES), "lineage": "EXACT_WITH_GENERATION_REBIND", "corpusPath": FIXTURE_PATH, "corpusAvailability": "TEST_LANE_COORDINATED", "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows}


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    required_semantics = {"contractNames": list(CONTRACT_NAMES), "subjectKinds": list(SUBJECT_KINDS), "reviewStates": list(REVIEW_STATES), "dispositionKinds": list(DISPOSITION_KINDS), "changeItemKinds": list(CHANGE_ITEM_KINDS), "changeRequestStates": list(("OPEN", "RESOLVED", "WITHDRAWN", "SUPERSEDED")), "evidenceKinds": list(EVIDENCE_KINDS), "actionPriorities": list(ACTION_PRIORITIES), "actionStates": list(ACTION_STATES), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": list(FORBIDDEN_CLAIMS)}
    return _sealed({"schema": "V23P03C14ReviewAndCorrectiveActionContractV1", "artifact": "V23P03C14ReviewAndCorrectiveActionContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "orderingAuthority": ORDERING_AUTHORITY, "schemaArtifact": schema_row, "sourceContract": _source_contract(source_rows, authority_rows), "semanticScope": SEMANTIC_SCOPE, "requiredSemantics": required_semantics, "corpusShape": TEST_CORPUS_SHAPE, "persistenceBoundary": PERSISTENCE, "requiredLifecycle": list(LIFECYCLE_DIMENSIONS), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "successor": {"cardID": "V23-P03-C15", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {"contractNames": list(CONTRACT_NAMES), "reviewStates": list(REVIEW_STATES), "dispositionKinds": list(DISPOSITION_KINDS), "changeRequestStates": list(("OPEN", "RESOLVED", "WITHDRAWN", "SUPERSEDED")), "actionPriorities": list(ACTION_PRIORITIES), "actionStates": list(ACTION_STATES), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "requiredLifecycle": list(LIFECYCLE_DIMENSIONS)}
    return _sealed({"schema": "V23P03C14ReviewAndCorrectiveActionEvidenceReceiptV1", "artifact": "V23P03C14ReviewAndCorrectiveActionEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "orderingAuthority": ORDERING_AUTHORITY, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows), "schemaArtifact": schema_row, "contractArtifact": contract_row, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics), "corpusShapeDigest": sha256_value(TEST_CORPUS_SHAPE), "persistenceBoundary": PERSISTENCE, "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({"schema": "V23P03C14BrandImpactManifestV1", "artifact": "V23P03C14BrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI", "affectedSurfacePaths": [], "semanticStates": list(REVIEW_STATES) + list(ACTION_STATES), "contractArtifact": contract_row, "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


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
    contract_row = {"path": CONTRACT_PATH, "bytes": len(contract_raw), "sha256": sha256_bytes(contract_raw)}
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, json.loads(contract_raw.decode("utf-8"))))
    brand_raw = pretty(brand_document(json.loads(contract_raw.decode("utf-8"))))
    rendered = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({"schema": "V23P03C14ToolingManifestV1", "artifact": "V23P03C14ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE), "manifestInputCount": len(MANIFEST_INPUT_PATHS), "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "artifacts": manifest_rows, "artifactSetDigest": sha256_value(manifest_rows), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "orderingAuthority": ORDERING_AUTHORITY, "persistenceBoundary": PERSISTENCE, "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered

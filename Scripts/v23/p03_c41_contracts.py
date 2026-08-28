"""Deterministic static corpus and evidence builders for V23-P03-C41.

This module is intentionally a sealed, static-only tooling lane.  It records
the C41 functional-relationship contract, its source/fence evidence, and a
synthetic hostile/recovery corpus.  It never evaluates customer data, stores a
current projection row, creates a second graph/store/writer, fetches a source,
or claims native, hosted, adoption, acceptance, or release evidence.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C41"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 49
BASE_HEAD = "a3dbaeec868333f5940efa9bf5acf7811aed6d25"
BASE_TREE = "ac9539fcbfdcaa0816ac124753f0e1ed515361c1"
CONTEXT_DIGEST = "2a812d74def7b09e4339a99919fcaed0ac7f96ab750622fceb0c0e2280845364"
FENCE_DIGEST = "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000"
PREREQUISITE_DIGEST = "a6f537839f545ec8114ef00240734913358b373ac8c4ae464f59c2b57562f74b"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
COORDINATION_HEAD = "9a4ac5b29d5392f681f9a0801594b08132067c1a"
COORDINATION_TREE = "6f700a769efc21a659ed89fd47337cf75e8f5be1"
COORDINATION_LEDGER_DIGEST = "4fc9c4f984bb6a0f8ffd7aa2009ef4c8fe8ce8f46f832bc6ac32bba4bb8d42f0"
COORDINATION_CAS_SEQUENCE = 208
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "d19b56ccb81486823c0c5392a3114a25fc8694d9c537b87202261fd9663b1e87"
DOSSIER_SHA256 = "2b331770b8b96683f96985a9ca4a3b664192aaa0e46cdf9d76ab52afa004baec"
DOSSIER_UTF8_LENGTH = 7130
INHERITED_V21_BLOCK_SHA256 = "75aac59a81fb82ffff45c1a09ca4bb62fff4969baf9779cc368667a92655d7ee"
INHERITED_V21_BLOCK_UTF8_LENGTH = 6986

SCHEMA_PATH = "Scripts/v23/functional-relationship.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C41FunctionalRelationshipContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C41FunctionalRelationshipEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C41BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C41-tooling-manifest.json"
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/FunctionalRelationships/V21P03C41FunctionalRelationshipCorpusV1.json"

SCRIPT_PATHS = (
    "Scripts/v23/p03_c41_contracts.py",
    "Scripts/v23/generate_p03_c41_contracts.py",
    "Scripts/v23/verify_p03_c41_contracts.py",
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
    "FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetSemanticPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/AssetSemantics/AssetSemanticsCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetSemanticLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
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
    "FieldEvidenceAppTests/V9_24AssetSemanticLifecycleTests.swift",
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
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/FunctionalRelationships/FunctionalRelationshipContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/FunctionalRelationshipPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/FunctionalRelationships/FunctionalRelationshipCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/FunctionalRelationships/FunctionalRelationshipLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_26FunctionalRelationshipTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/FunctionalRelationships/V21P03C41FunctionalRelationshipCorpusV1.json",
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

# Compact, exact owner rows derived from the C41 fence's authorized edges.
PRIOR_FENCE_OVERLAPS = (
    {"cardID": "V23-P00-C11", "fenceDigest": "560b3bd0401d0da46bcedc9f7184c8041e198db8cbe8af3011731fc0ad6cc8b1", "disposition": "ERASE_CONCURRENCY_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P01-C01", "fenceDigest": "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", "disposition": "SCHEMA_SUCCESSOR_AND_MIGRATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C02", "fenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", "disposition": "OWNED_FILE_RESTORE_CLONE_FORK_AND_GENERATION_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P01-C03", "fenceDigest": "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", "disposition": "COPY_ON_WRITE_MIGRATION_RECOVERY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P01-C04", "fenceDigest": "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", "disposition": "ARCHIVE_AND_OPEN_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C05", "fenceDigest": "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", "disposition": "CANONICAL_BACKUP_RESTORE_AND_IDENTITY_REPROOF_REQUIRED", "overlapCount": 12},
    {"cardID": "V23-P01-C06", "fenceDigest": "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", "disposition": "DELETE_ERASE_AND_PORTABLE_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 23},
    {"cardID": "V23-P01-C07", "fenceDigest": "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", "disposition": "RELEASED_DATA_AND_HISTORIC_REPORT_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 7},
    {"cardID": "V23-P02-C01", "fenceDigest": "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", "disposition": "SOLE_WRITER_AND_COMMAND_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P02-C02", "fenceDigest": "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", "disposition": "MUTATION_RECEIPT_JOURNAL_AND_RECOVERY_REPROOF_REQUIRED", "overlapCount": 29},
    {"cardID": "V23-P02-C03", "fenceDigest": "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", "disposition": "SYNC_CLASSIFICATION_AND_CONFLICT_REPROOF_REQUIRED", "overlapCount": 21},
    {"cardID": "V23-P02-C04", "fenceDigest": "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", "disposition": "GENERATION_LEASE_AND_STALE_WRITER_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P02-C05", "fenceDigest": "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", "disposition": "RESUMABLE_JOB_BOUNDARY_REPROOF_REQUIRED", "overlapCount": 8},
    {"cardID": "V23-P02-C06", "fenceDigest": "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", "disposition": "DEVICE_TIME_AND_PROTECTED_DATA_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P02-C07", "fenceDigest": "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", "disposition": "OBSERVATION_TIME_AND_PROJECTION_REPROOF_REQUIRED", "overlapCount": 26},
    {"cardID": "V23-P02-C08", "fenceDigest": "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", "disposition": "SYSTEM_HEALTH_CLASSIFICATION_REPROOF_REQUIRED", "overlapCount": 4},
    {"cardID": "V23-P02-C09", "fenceDigest": "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", "disposition": "PERSISTENT_KIND_LIFECYCLE_COVERAGE_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C01", "fenceDigest": "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3", "disposition": "PACKAGE_REGISTRY_AND_CAPABILITY_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P03-C02", "fenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba", "disposition": "PACKAGE_RELEASE_BINDING_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P03-C06", "fenceDigest": "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2", "disposition": "COMPLETED_SNAPSHOT_IMMUTABILITY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P03-C07", "fenceDigest": "3f6a36f8794c159c24c26ec06506bff77a2d998df3cf04a5b8b06bb1d56e8264", "disposition": "KERNEL_BACKUP_RESTORE_DELETE_ERASE_REGISTRY_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P03-C08", "fenceDigest": "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", "disposition": "PACK_LIFECYCLE_BACKUP_RESTORE_AND_DELETE_REPROOF_REQUIRED", "overlapCount": 9},
    {"cardID": "V23-P03-C09", "fenceDigest": "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", "disposition": "SEARCH_SCHEMA_REBUILD_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 39},
    {"cardID": "V23-P03-C10", "fenceDigest": "7e90b5eb871c6560b395fb487d0155a31a499009c6a2d4303b0aa668476d80f8", "disposition": "PORTABLE_KERNEL_CONFORMANCE_HARNESS_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P03-C11", "fenceDigest": "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", "disposition": "JOURNAL_CHECKPOINT_AND_REPLAY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C12", "fenceDigest": "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "disposition": "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED", "overlapCount": 29},
    {"cardID": "V23-P03-C16", "fenceDigest": "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "disposition": "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P03-C35", "fenceDigest": "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "disposition": "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED", "overlapCount": 37},
    {"cardID": "V23-P03-C38", "fenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", "disposition": "ACCOUNTABILITY_ACTOR_QUALIFICATION_SNAPSHOT_REPROOF_REQUIRED", "overlapCount": 48},
    {"cardID": "V23-P03-C39", "fenceDigest": "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2", "disposition": "ASSET_SEMANTICS_SUBJECT_PACKAGE_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 56},
    {"cardID": "V23-P03-C40", "fenceDigest": "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397", "disposition": "DIRECT_PREREQUISITE_AUTHORITY_AND_SHARED_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 64},
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 49,
    "priorOwnedPathCount": 823,
    "overlapCount": 474,
    "authorizedOverlapCount": 474,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = (
    "FunctionalRelationshipTypeDescriptorV1",
    "AssetFunctionalRelationshipEventV1",
    "CurrentFunctionalRelationshipProjectionV1",
    "FunctionalRelationshipDispositionPreviewV1",
    "CompletedFunctionalRelationshipSnapshotV1",
)
RELATIONSHIP_KINDS = ("CONTROLS", "SERVES", "MONITORS", "SUPPLIES", "SUPPORTS", "ASSOCIATES")
ENDPOINT_KINDS = ("ASSET", "COMPOSITION_COMPONENT", "SITE")
DIRECTIONS = ("DIRECTED", "SYMMETRIC")
EVENT_KINDS = ("ADDED", "ENDED", "SUPERSEDED")
DISPOSITIONS = ("ALLOWED", "DENIED", "INCOMPLETE", "REVIEW_REQUIRED")
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V12_VERSIONED_IDENTITY",
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
    "INTERRUPTION_IDEMPOTENT_RECEIPTS",
)
FORBIDDEN_CLAIMS = (
    "STRUCTURAL_COMPOSITION_OR_PLACEMENT",
    "OWNERSHIP_OR_AUTHORIZATION",
    "CASCADE_DELETION_OR_IDENTITY_MERGE",
    "USER_CREATED_RELATIONSHIP_TYPES",
    "ARBITRARY_RELATIONSHIP_PAYLOAD",
    "UNBOUNDED_GRAPH_OR_SOLVER",
    "GIS_TELEMETRY_OR_REMOTE_COMMAND",
    "SECOND_GRAPH_STORE_OR_WRITER",
    "CURRENT_PROJECTION_PERSISTENCE",
    "C35_STRUCTURAL_MUTATION",
    "S10_RELEASE_OR_BRAND_APPROVAL",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV9_FunctionalRelationshipG01DescriptorEventAndFrozenSnapshotMatrix",
    "testV9_FunctionalRelationshipA01EndpointCardinalityCycleAndTraversalBoundaries",
    "testV9_FunctionalRelationshipH01CrossWorkspaceSelfEdgeAndC35OwnershipFailClosed",
    "testV9_FunctionalRelationshipI01InterruptedMigrationMutationProjectionAndReplayRecover",
    "testV9_FunctionalRelationshipR01BackupRestoreSearchReportDeleteEraseAndHistoryPreserve",
)
SOURCE_CONTRACT_TOKENS = (CARD, "V21-P03-C41", *CONTRACT_NAMES)

SEMANTIC_SCOPE = {
    "durableOwner": [*CONTRACT_NAMES, "PersistentSchemaV12"],
    "relationshipPolicy": "PACKAGE_RELEASE_QUALIFIED_BOUNDED_FUNCTIONAL_ASSOCIATIONS_ONLY_WITH_STABLE_SEMANTIC_IDS_DIRECTION_SYMMETRY_CARDINALITY_SELF_EDGE_CYCLE_TRAVERSAL_HARD_EDGE_AND_SITE_POLICY",
    "structuralBoundaryPolicy": "C35_REMAINS_SOLE_STRUCTURAL_ASSET_COMPOSITION_OWNER_AND_FUNCTIONAL_RELATIONSHIPS_NEVER_IMPLY_PLACEMENT_CONTAINMENT_OWNERSHIP_AUTHORIZATION_COMPLIANCE_TELEMETRY_OR_CASCADE_DELETION",
    "eventPolicy": "APPEND_ONLY_ADDED_ENDED_SUPERSEDED_EVENTS_REBUILD_ONE_NONPERSISTENT_CURRENT_PROJECTION_AND_NEVER_CREATE_A_SECOND_GRAPH_STORE_OR_WRITER",
    "snapshotPolicy": "COMPLETED_WORK_BINDS_EXACT_RELEVANT_RELATIONSHIPS_AND_DESCRIPTOR_RELEASES_AND_LATER_ENDPOINT_OR_RELATIONSHIP_CHANGE_NEVER_REWRITES_FINISHED_WORK",
    "validationPolicy": "ENFORCE_ENDPOINT_TYPE_WORKSPACE_SELF_EDGE_MAXIMUM_CARDINALITY_CYCLE_TRAVERSAL_AND_SITE_BOUNDS_AT_MUTATION_AND_MINIMUM_ONLY_AT_NAMED_READINESS_FINALIZATION_OR_ATOMIC_BUNDLE",
    "dispositionPolicy": "MOVE_REPARENT_REPLACEMENT_RETIREMENT_DELETE_RESTORE_IDENTITY_RECONCILIATION_IMPORT_BULK_PACKAGE_RETIREMENT_AND_CROSS_SITE_CHANGE_PRODUCE_ZERO_WRITE_PREVIEWS",
    "migrationPolicy": "V11_TO_V12_COPY_ON_WRITE_PRESERVES_RELEASED_VALUES_AND_CREATES_ZERO_RELATIONSHIP_DESCRIPTORS_EVENTS_PROJECTIONS_OR_COMPLETED_SNAPSHOTS",
    "writerPolicy": "P02_C01_SOLE_WORKSPACE_WRITER_COMMITS_EXPECTED_REVISION_MUTATION_ID_ATOMIC_POST_IMAGE_DURABLE_RECEIPT_JOURNAL_AND_EFFECT_BEFORE_RECEIPT_RECOVERY",
    "fullLifecyclePolicy": "SCHEMA_MIGRATION_COMPATIBILITY_BACKUP_RESTORE_CLONE_FORK_IMPORT_EXPORT_JOURNAL_REPLAY_SEARCH_REBUILD_DELETE_ERASE_REPORT_FROZEN_DISPLAY_PRIVACY_INTERRUPTION_AND_DOWNGRADE_ENROLL_DESCRIPTOR_EVENT_AND_SNAPSHOT_FAMILIES_BEFORE_FIRST_WRITE",
    "forbiddenPolicy": "NO_USER_CREATED_TYPES_ARBITRARY_PAYLOAD_UNBOUNDED_GRAPH_SOLVER_GIS_TELEMETRY_REMOTE_COMMAND_CASCADE_DELETE_INFERRED_LINK_SECOND_GRAPH_STORE_WRITER_OR_PACKAGE_SPECIFIC_GRAPH",
    "localizationAccessibilityPolicy": "EXISTING_TYPED_LOCALIZED_KEYS_ACCESSIBLE_TEXTUAL_DIRECTION_AND_STATE_DYNAMIC_TYPE_VOICEOVER_RTL_AND_NONCOLOR_SEMANTICS_WITH_NO_NEW_UI_SURFACE",
    "privacyPolicy": "CUSTOMER_SAFE_SEARCH_REPORT_AND_OPEN_JSON_EXCLUDE_PRIVATE_LOCATORS_AND_UNSUPPORTED_OPERATIONAL_OWNERSHIP_AUTHORIZATION_OR_COMPLIANCE_CLAIMS",
    "s10Policy": "EXACT_EIGHTY_SIX_PATH_RESERVATION_IS_FROZEN_AND_CARD_PATH_FENCE_HAS_ZERO_S10_OVERLAP",
    "activationPolicy": "PROVISIONAL_PRE_S10_NONRESERVED_SCHEMA_CONTRACT_LIFECYCLE_FIXTURE_AND_TEST_IMPLEMENTATION_ONLY_NATIVE_HOSTED_RELEASE_AND_PHASE10_POLLING_DEFERRED_PENDING_ACCEPTED_S10_6_RECONCILIATION",
}

REQUIRED_BEHAVIORS = (
    {"id": "DESCRIPTOR_RELEASES", "contract": "FunctionalRelationshipTypeDescriptorV1", "requirement": "Immutable package-release descriptors bind stable semantic relationship IDs, endpoint kinds, direction or symmetry, cardinality, self-edge, cycle, traversal, hard-edge, and Site/workspace policy without becoming structural composition.", "evidence": "C41-S01"},
    {"id": "APPEND_ONLY_EVENTS", "contract": "AssetFunctionalRelationshipEventV1", "requirement": "ADDED, ENDED, and SUPERSEDED events preserve stable relationship IDs, endpoint AssetIDs, descriptor releases, effective and recorded time, expected revisions, actor provenance, and mutation receipts.", "evidence": "C41-S02"},
    {"id": "ONE_REBUILDABLE_PROJECTION", "contract": "CurrentFunctionalRelationshipProjectionV1", "requirement": "A current projection is rebuilt from descriptor and event history and is explicitly nonpersistent; no second graph truth, graph store, or writer exists.", "evidence": "C41-S03"},
    {"id": "DISPOSITION_PREVIEWS", "contract": "FunctionalRelationshipDispositionPreviewV1", "requirement": "Move, reparent, replacement, retirement, delete, restore, identity reconciliation, import, package retirement, and cross-Site changes produce zero-write reviewed previews.", "evidence": "C41-S04"},
    {"id": "FROZEN_SNAPSHOTS", "contract": "CompletedFunctionalRelationshipSnapshotV1", "requirement": "Completed work binds exact relationship and descriptor-release history; later endpoint or relationship changes never rewrite a finished snapshot or report.", "evidence": "C41-S05"},
    {"id": "SCHEMA_V12_RECORDS11", "contract": "PersistentSchemaV12", "requirement": "V11-to-V12 copy-on-write migration enrolls descriptor and event records at records schema 11 while creating zero relationship rows for legacy data and preserving compatibility and recovery.", "evidence": "C41-L01"},
    {"id": "C35_BOUNDARY", "contract": "V23-P03-C41", "requirement": "C35 remains read-only to this lane and remains the sole structural AssetCompositionEdge owner; C41 never infers placement, containment, ownership, authorization, compliance, telemetry, or cascade deletion.", "evidence": "C41-B02"},
    {"id": "STATIC_BOUNDARY", "contract": CARD, "requirement": "This lane is PASS_STATIC_PROVISIONAL; native, hosted, adoption, acceptance, release, acceptance credit, and release credit remain false.", "evidence": "C41-B01"},
)
EVIDENCE_CASES = (
    {"id": "C41-S01", "kind": "DESCRIPTOR_POLICY", "assertion": "Synthetic descriptor releases cover relationship kind, endpoint type, direction or symmetry, cardinality, self-edge, cycle, traversal, hard-edge, and same-Site policy."},
    {"id": "C41-S02", "kind": "EVENT_HISTORY", "assertion": "Synthetic ADDED, ENDED, and SUPERSEDED event history is append-only and pins descriptor releases, endpoints, revisions, mutation IDs, and provenance."},
    {"id": "C41-S03", "kind": "NONPERSISTENT_PROJECTION", "assertion": "The current projection is explicitly rebuildable and has zero persisted rows; no second graph truth, store, or writer is admitted."},
    {"id": "C41-S04", "kind": "DISPOSITION_PREVIEW", "assertion": "Endpoint and package lifecycle changes yield typed zero-write dispositions rather than implicit relationship mutation or cascade deletion."},
    {"id": "C41-S05", "kind": "FROZEN_SNAPSHOT", "assertion": "Completed work preserves exact relationship and descriptor-release history across later endpoint and relationship changes."},
    {"id": "C41-H01", "kind": "HOSTILE_BOUNDARY", "assertion": "Cross-workspace, wrong endpoint type, self-edge, cardinality, cycle, traversal, cross-Site, unqualified package, C35 structural, inferred-link, and second-store attempts fail closed."},
    {"id": "C41-L01", "kind": "LIFECYCLE_COVERAGE", "assertion": "V12 records-11 migration, compatibility, backup/restore, clone/fork, import/export, journal/replay, search/rebuild, report, delete/Erase, privacy, interruption, and downgrade are declared before first write."},
    {"id": "C41-F01", "kind": "PATH_DIGEST_FENCE", "assertion": "Exactly the 91-path C41 fence is accounted for (77 existing and 14 new), with exact manifest byte/digest rows, authorized prior overlap proof, and zero S10 overlap."},
    {"id": "C41-B01", "kind": "STATIC_BOUNDARY", "assertion": "The result is PASS_STATIC_PROVISIONAL and all native, hosted, adoption, acceptance, release, and credit flags remain false."},
)

SOURCE_PROJECTION = {
    "registerRows": ["| 49 | <a id=\"v23-p03-c41-register\"></a>[`V23-P03-C41`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c41) | Bounded functional asset associations, effective-dated topology history, and frozen work snapshots | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C40` | `EXACT_WITH_GENERATION_REBIND` |"],
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
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C41).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C14", "V23-P06-C10", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
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
    "ordinaryDirectEdgeCount": 1,
    "nonreleaseSpecialEdgeApplied": False,
    "canonicalRelationPreserved": True,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "predecessors": [{
        "cardID": "V23-P03-C40",
        "attemptID": 1,
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "checkpointDigest": "1580e2692e9ab050a8e7947b54ed57b129e860b61762f80e9549cfe90cb263bb",
        "contextDigest": "fafbec0ccdb5cd65f331caca8fa74373104f31f38b1be9abd97345410bd82c9e",
        "pathFenceDigest": "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397",
        "verificationReceiptDigest": "e1046caa5eb0a7532361aafc11e10d9758d897d997674591ec91afbf4db3fefd",
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AND_ORDERING_AUTHORITY_AT_EXACT_APP_HEAD",
    }],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
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
        schemas = {_schema_for_value(item).__repr__(): _schema_for_value(item) for item in value}
        if schemas:
            result["items"] = next(iter(schemas.values())) if len(schemas) == 1 else {"anyOf": [schemas[key] for key in sorted(schemas)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(f"unsupported schema value: {type(value)!r}")


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/functional-relationship.schema.json", "title": "V23 P03 C41 Functional Relationship Corpus"})
    return document


def _flags() -> dict[str, bool]:
    return {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False, "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False}


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C40"], "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "PERSISTENT_SCHEMA_V12_FUNCTIONAL_RELATIONSHIPS", "recordSchemaVersion": 11,
        "schemaBehaviorDelta": True, "migrationBehaviorDelta": True, "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True, "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V12_WRITE", "uiSurfaceDelta": False, "brandSurfaceDelta": False,
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
        "schema": "V23P03C41FunctionalRelationshipContractV1", "artifact": "V23P03C41FunctionalRelationshipContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "schemaArtifact": schema_row, "sourceContract": _source_contract(source_rows, authority_rows),
        "semanticScope": SEMANTIC_SCOPE, "requiredSemantics": {"contractNames": list(CONTRACT_NAMES), "relationshipKinds": list(RELATIONSHIP_KINDS), "endpointKinds": list(ENDPOINT_KINDS), "directions": list(DIRECTIONS), "eventKinds": list(EVENT_KINDS), "dispositions": list(DISPOSITIONS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": list(FORBIDDEN_CLAIMS)},
        "persistenceBoundary": CORPUS["persistence"], "requiredLifecycle": list(LIFECYCLE_DIMENSIONS), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES),
        "successor": {"cardID": "V23-P03-C42", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {"contractNames": list(CONTRACT_NAMES), "relationshipKinds": list(RELATIONSHIP_KINDS), "endpointKinds": list(ENDPOINT_KINDS), "directions": list(DIRECTIONS), "eventKinds": list(EVENT_KINDS), "dispositions": list(DISPOSITIONS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "requiredLifecycle": list(LIFECYCLE_DIMENSIONS)}
    return _sealed({
        "schema": "V23P03C41FunctionalRelationshipEvidenceReceiptV1", "artifact": "V23P03C41FunctionalRelationshipEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows),
        "schemaArtifact": schema_row, "contractArtifact": contract_row, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics),
        "persistenceBoundary": CORPUS["persistence"], "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C41BrandImpactManifestV1", "artifact": "V23P03C41BrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI",
        "affectedSurfacePaths": [], "semanticStates": ["INCOMPLETE", "ALLOWED", "DENIED", "REVIEW_REQUIRED"], "contractArtifact": contract_row,
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
    contract_row = {"path": CONTRACT_PATH, "bytes": len(contract_raw), "sha256": sha256_bytes(contract_raw)}
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, json.loads(contract_raw.decode("utf-8"))))
    brand_raw = pretty(brand_document(json.loads(contract_raw.decode("utf-8"))))
    rendered: dict[str, bytes] = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "schema": "V23P03C41ToolingManifestV1", "artifact": "V23P03C41ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
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


CORPUS: dict[str, Any] = {
    "schema": "V21P03C41FunctionalRelationshipCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "requiredContractNames": list(CONTRACT_NAMES),
    "relationshipKinds": list(RELATIONSHIP_KINDS),
    "endpointKinds": list(ENDPOINT_KINDS),
    "directions": list(DIRECTIONS),
    "eventKinds": list(EVENT_KINDS),
    "dispositions": list(DISPOSITIONS),
    "persistence": {
        "schemaRelease": "PERSISTENT_SCHEMA_V12_FUNCTIONAL_RELATIONSHIPS",
        "recordSchemaVersion": 11,
        "predecessorSchemaVersion": 11,
        "predecessorRecordSchemaVersion": 10,
        "migration": "EXACT_V11_TO_V12_COPY_ON_WRITE",
        "canonicalWriter": "V23-P02-C01",
        "lifecycleOwner": CARD,
        "firstWriteEnrolled": True,
        "compatibilityRequired": True,
        "backupRestoreRequired": True,
        "deleteEraseRequired": True,
        "exportImportPreviewRequired": True,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V12_WRITE",
        "persistedFamilies": ["FunctionalRelationshipTypeDescriptorV1", "AssetFunctionalRelationshipEventV1"],
        "descriptorEventOnlyPersistence": True,
        "nonPersistentFamilies": ["CurrentFunctionalRelationshipProjectionV1", "FunctionalRelationshipDispositionPreviewV1"],
        "snapshotBinding": "CompletedFunctionalRelationshipSnapshotV1_IN_EXISTING_COMPLETED_ACTIVITY_SNAPSHOT",
        "currentProjectionRows": 0,
        "currentProjectionRowCount": 0,
        "recordsSchemaVersion": 11,
        "secondGraphStore": False,
        "secondWriter": False,
        "c35ReadOnly": True,
        "legacyRelationshipRowsCreated": 0,
    },
    "relationshipDescriptors": [
        {"id": "descriptor-controls-v1", "semanticID": "controls", "relationshipKind": "CONTROLS", "packageReleaseID": "package-c41-v1", "fromEndpointKind": "ASSET", "toEndpointKind": "ASSET", "direction": "DIRECTED", "symmetric": False, "minimumCardinality": 0, "maximumCardinality": 1, "selfEdgeAllowed": False, "cyclePolicy": "DENY", "maximumTraversalDepth": 4, "hardEdge": True, "sameSiteRequired": True, "workspaceRequired": True, "qualifiedByC39": True, "localizedKey": "functional.relationship.controls", "released": True},
        {"id": "descriptor-serves-v1", "semanticID": "serves", "relationshipKind": "SERVES", "packageReleaseID": "package-c41-v1", "fromEndpointKind": "ASSET", "toEndpointKind": "COMPOSITION_COMPONENT", "direction": "DIRECTED", "symmetric": False, "minimumCardinality": 0, "maximumCardinality": 8, "selfEdgeAllowed": False, "cyclePolicy": "DENY", "maximumTraversalDepth": 6, "hardEdge": False, "sameSiteRequired": True, "workspaceRequired": True, "qualifiedByC39": True, "localizedKey": "functional.relationship.serves", "released": True},
        {"id": "descriptor-associates-v1", "semanticID": "associates", "relationshipKind": "ASSOCIATES", "packageReleaseID": "package-c41-v1", "fromEndpointKind": "ASSET", "toEndpointKind": "ASSET", "direction": "SYMMETRIC", "symmetric": True, "minimumCardinality": 0, "maximumCardinality": 2, "selfEdgeAllowed": False, "cyclePolicy": "DENY", "maximumTraversalDepth": 2, "hardEdge": False, "sameSiteRequired": True, "workspaceRequired": True, "qualifiedByC39": True, "localizedKey": "functional.relationship.associates", "released": True},
    ],
    "relationshipEvents": [
        {"id": "event-added-1", "eventKind": "ADDED", "relationshipID": "relationship-1", "descriptorReleaseID": "descriptor-controls-v1", "workspaceID": "workspace-synthetic-1", "siteID": "site-synthetic-1", "sourceAssetID": "asset-source-1", "targetAssetID": "asset-target-1", "effectiveAt": "2024-01-01T10:00:00Z", "recordedAt": "2024-01-01T10:01:00Z", "actorID": "actor-synthetic-1", "mutationID": "mutation-added-1", "expectedRevision": 1, "predecessorEventID": None, "supersedesEventID": None},
        {"id": "event-ended-1", "eventKind": "ENDED", "relationshipID": "relationship-1", "descriptorReleaseID": "descriptor-controls-v1", "workspaceID": "workspace-synthetic-1", "siteID": "site-synthetic-1", "sourceAssetID": "asset-source-1", "targetAssetID": "asset-target-1", "effectiveAt": "2024-02-01T10:00:00Z", "recordedAt": "2024-02-01T10:01:00Z", "actorID": "actor-synthetic-1", "mutationID": "mutation-ended-1", "expectedRevision": 2, "predecessorEventID": "event-added-1", "supersedesEventID": None},
        {"id": "event-added-2", "eventKind": "ADDED", "relationshipID": "relationship-2", "descriptorReleaseID": "descriptor-serves-v1", "workspaceID": "workspace-synthetic-1", "siteID": "site-synthetic-1", "sourceAssetID": "asset-source-1", "targetAssetID": "component-target-1", "effectiveAt": "2024-03-01T10:00:00Z", "recordedAt": "2024-03-01T10:01:00Z", "actorID": "actor-synthetic-1", "mutationID": "mutation-added-2", "expectedRevision": 3, "predecessorEventID": "event-ended-1", "supersedesEventID": None},
        {"id": "event-superseded-2", "eventKind": "SUPERSEDED", "relationshipID": "relationship-2", "descriptorReleaseID": "descriptor-serves-v1", "workspaceID": "workspace-synthetic-1", "siteID": "site-synthetic-1", "sourceAssetID": "asset-source-1", "targetAssetID": "component-target-1", "effectiveAt": "2024-04-01T10:00:00Z", "recordedAt": "2024-04-01T10:01:00Z", "actorID": "actor-synthetic-1", "mutationID": "mutation-superseded-2", "expectedRevision": 4, "predecessorEventID": "event-added-2", "supersedesEventID": "event-added-2"},
    ],
    "currentProjectionRows": [],
    "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY",
    "c35ReadOnly": True,
    "dispositionPreviews": [
        {"id": "preview-endpoint-move", "operation": "MOVE", "writes": 0, "disposition": "REVIEW_REQUIRED", "historyPreserved": True},
        {"id": "preview-endpoint-delete", "operation": "DELETE", "writes": 0, "disposition": "DENIED", "historyPreserved": True},
        {"id": "preview-cross-site", "operation": "CROSS_SITE_CHANGE", "writes": 0, "disposition": "DENIED", "historyPreserved": True},
    ],
    "completedSnapshots": [{"id": "snapshot-synthetic-1", "workspaceID": "workspace-synthetic-1", "siteID": "site-synthetic-1", "relationshipIDs": ["relationship-1", "relationship-2"], "descriptorReleaseIDs": ["descriptor-controls-v1", "descriptor-serves-v1"], "frozen": True, "rewriteOnLaterChange": False, "boundInCompletedActivity": True}],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED"} for case_id in (
        "cross-workspace", "wrong-endpoint-type", "self-edge", "maximum-cardinality", "cycle", "traversal-overflow", "hard-edge-overflow", "cross-site", "unqualified-package", "package-retired", "c35-structural-edge", "placement-inference", "ownership-inference", "inferred-link", "cascade-delete", "current-projection-row", "second-graph-store", "second-writer", "arbitrary-payload", "user-created-type",
    )],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "RETRY_IDEMPOTENT_NO_PARTIAL_ACTIVATION"} for case_id in (
        "migration-boundary", "descriptor-admission-boundary", "event-boundary", "projection-rebuild-boundary", "disposition-boundary", "snapshot-boundary", "archive-boundary", "restore-boundary", "replay-boundary",
    )],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "RECOVER_EFFECT_RECEIPT_AND_HISTORY"} for case_id in (
        "backup-clone-fork", "journal-replay-checkpoint", "compatibility-forward-fix", "search-rebuild", "report-open-json", "delete-erase", "released-v1", "cross-site-disposition",
    )],
    "claims": {claim: False for claim in (*FORBIDDEN_CLAIMS, "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit")},
}

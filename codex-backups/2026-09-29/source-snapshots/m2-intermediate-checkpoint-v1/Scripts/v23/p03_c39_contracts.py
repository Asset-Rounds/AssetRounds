"""Deterministic static contract corpus and artifact builders for V23-P03-C39.

Card 47 owns the asset-semantics evidence lane.  This module is deliberately
static: it projects the accepted V23 dossier, the inherited V21 semantic
payload, the frozen 73-path fence, and a synthetic fixture without claiming
native compilation, hosted behavior, adoption, acceptance, or release.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C39"
SCHEMA_VERSION = 1
BASE_HEAD = "f612cc70d8962a4ace80cd231b1079cc53240ec4"
BASE_TREE = "4a7340b1552a9e96332f3b709d45ac43a34f01aa"
CONTEXT_DIGEST = "c17b4ad987ed57fb4a44ba6adaa53b19d9ea0e2d6de33b79736fd66063301329"
FENCE_DIGEST = "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2"
PREREQUISITE_DIGEST = "966fd06cdcd43f5c7eb3adebb3d634cf48f79fba3bf7fbd82bd6ebc94037b3e0"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
COORDINATION_HEAD = "1e7346c5b5aed63ee8581ff9f1f75ce4082009d7"
COORDINATION_TREE = "77c32d078217a1176bd8880819943f3d35390d28"
COORDINATION_LEDGER_DIGEST = "5da238bc70a820bba4786786364edeff2a92a462b13e5a46f44b89fe52a19b4d"
COORDINATION_PROJECTION_DIGEST = "6a2edf5ce35c4b305b86ac8a07888ccd86d778e1d60b80eaa7c07ecb99d8631f"
COORDINATION_CAS_SEQUENCE = 200
HYDRATION_REVISION = 4
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "382e7f442afbc3738dbe838cd80f2dbbecdb1c860d7a148d48d4fac947af02fd"
REGISTER_ROW_UTF8_LENGTH = 302
DOSSIER_SHA256 = "f4f5247126b79823f6b64aac2b18fb709e4c1ffb73a09b943fa250dc959777b0"
DOSSIER_UTF8_LENGTH = 7129
INHERITED_V21_BLOCK_SHA256 = "4126797b486788308ad9871922d3f72d561f09ce8180d10b437222fe3c3bea0b"
INHERITED_V21_BLOCK_UTF8_LENGTH = 7588

SCHEMA_PATH = "Scripts/v23/asset-semantics.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C39AssetSemanticsContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C39AssetSemanticsEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C39BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C39-tooling-manifest.json"
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/AssetSemantics/V21P03C39AssetSemanticCorpusV1.json"

SCRIPT_PATHS = (
    "Scripts/v23/p03_c39_contracts.py",
    "Scripts/v23/generate_p03_c39_contracts.py",
    "Scripts/v23/verify_p03_c39_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

# The order is hydrated authority order.  Existing paths are exact BASE_HEAD
# blobs; the 15 new paths are the C39 product and static artifact lane.
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
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceApp/Domain/Models/Asset.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift",
    "FieldEvidenceApp/Domain/Location/AssetCompositionContractsV1.swift",
    "FieldEvidenceApp/Domain/Location/AssetPlacementContractsV1.swift",
    "FieldEvidenceApp/Application/Location/AssetPlacementChangeCoordinatorV1.swift",
    "FieldEvidenceAppTests/V9_11PackRegistryTests.swift",
    "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift",
)

NEW_PATHS = (
    "FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetSemanticPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/AssetSemantics/AssetSemanticsCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetSemanticLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_24AssetSemanticLifecycleTests.swift",
    "FieldEvidenceAppUITests/V23_P03_C39AssetSemanticLifecycleUITests.swift",
    FIXTURE_PATH,
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

# The hydration proof has 316 path edges over the 47 earlier V23 fences.
# Keep one compact row per authorized owner in generated artifacts; exact path
# ownership remains bound by the immutable source/fence digests and counts.
PRIOR_FENCE_OVERLAPS = (
    {"cardID": "V23-P01-C01", "fenceDigest": "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", "disposition": "SCHEMA_SUCCESSOR_AND_MIGRATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C02", "fenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", "disposition": "OWNED_FILE_RESTORE_CLONE_FORK_AND_GENERATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C03", "fenceDigest": "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", "disposition": "COPY_ON_WRITE_MIGRATION_RECOVERY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P01-C04", "fenceDigest": "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", "disposition": "ARCHIVE_AND_OPEN_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P01-C05", "fenceDigest": "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", "disposition": "CANONICAL_BACKUP_RESTORE_AND_IDENTITY_REPROOF_REQUIRED", "overlapCount": 10},
    {"cardID": "V23-P01-C06", "fenceDigest": "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", "disposition": "DELETE_ERASE_AND_PORTABLE_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 15},
    {"cardID": "V23-P01-C07", "fenceDigest": "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", "disposition": "RELEASED_DATA_AND_HISTORIC_REPORT_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P02-C01", "fenceDigest": "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", "disposition": "SOLE_WRITER_AND_COMMAND_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P02-C02", "fenceDigest": "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", "disposition": "MUTATION_RECEIPT_JOURNAL_AND_RECOVERY_REPROOF_REQUIRED", "overlapCount": 22},
    {"cardID": "V23-P02-C03", "fenceDigest": "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", "disposition": "SYNC_CLASSIFICATION_AND_CONFLICT_REPROOF_REQUIRED", "overlapCount": 17},
    {"cardID": "V23-P02-C04", "fenceDigest": "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", "disposition": "GENERATION_LEASE_AND_STALE_WRITER_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P02-C05", "fenceDigest": "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", "disposition": "RESUMABLE_JOB_BOUNDARY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P02-C06", "fenceDigest": "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", "disposition": "DEVICE_TIME_AND_PROTECTED_DATA_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P02-C07", "fenceDigest": "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", "disposition": "OBSERVATION_TIME_AND_PROJECTION_REPROOF_REQUIRED", "overlapCount": 24},
    {"cardID": "V23-P02-C08", "fenceDigest": "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", "disposition": "SYSTEM_HEALTH_CLASSIFICATION_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P02-C09", "fenceDigest": "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", "disposition": "PERSISTENT_KIND_LIFECYCLE_COVERAGE_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C01", "fenceDigest": "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3", "disposition": "PACKAGE_REGISTRY_AND_CAPABILITY_REPROOF_REQUIRED", "overlapCount": 4},
    {"cardID": "V23-P03-C02", "fenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba", "disposition": "PACKAGE_RELEASE_BINDING_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P03-C06", "fenceDigest": "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2", "disposition": "COMPLETED_SNAPSHOT_IMMUTABILITY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C08", "fenceDigest": "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", "disposition": "PACK_LIFECYCLE_BACKUP_RESTORE_AND_DELETE_REPROOF_REQUIRED", "overlapCount": 8},
    {"cardID": "V23-P03-C09", "fenceDigest": "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", "disposition": "SEARCH_SCHEMA_REBUILD_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 36},
    {"cardID": "V23-P03-C11", "fenceDigest": "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", "disposition": "JOURNAL_CHECKPOINT_AND_REPLAY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C12", "fenceDigest": "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "disposition": "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED", "overlapCount": 28},
    {"cardID": "V23-P03-C16", "fenceDigest": "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "disposition": "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED", "overlapCount": 7},
    {"cardID": "V23-P03-C35", "fenceDigest": "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "disposition": "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED", "overlapCount": 41},
    {"cardID": "V23-P03-C38", "fenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", "disposition": "ACCOUNTABILITY_SCHEMA_AND_FULL_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 48},
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 47,
    "priorOwnedPathCount": 791,
    "overlapCount": 316,
    "authorizedOverlapCount": 316,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
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
    "predecessors": [
        {
            "cardID": "V23-P03-C38",
            "attemptID": 1,
            "candidateHead": BASE_HEAD,
            "candidateTree": BASE_TREE,
            "checkpointDigest": "798bc7539aa29f305e5cf460acb1065c7c3691bf60fba0d63e6b542c314ebe5b",
            "contextDigest": "713964ef5d381dd4261950d11035a5c20ade1decdf615ecdbd39e1ab7953486d",
            "pathFenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4",
            "verificationReceiptDigest": "250094a8d61d5a1c762de3aa6aed2a927deddc72d9a8349dedf476d5c08d74c7",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AND_ORDERING_AUTHORITY_AT_EXACT_APP_HEAD",
        }
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

CONTRACT_NAMES = (
    "AssetSemanticCatalogReleaseV1",
    "AssetKindDefinitionV1",
    "AssetKindBindingEventV1",
    "AssetWorkflowCapabilityBindingEventV1",
    "AssetProductIdentityV1",
    "AssetLifecycleEventV1",
    "AssetSuccessorLinkV1",
    "WorkSubjectScopeSnapshotV1",
)
CATALOG_STATES = ("RELEASED", "RETIRED")
LIFECYCLE_STATES = (
    "COMMISSIONING_NOT_RECORDED",
    "ACTIVE_RECORDED",
    "RETIRED_RECORDED",
    "REPLACED_RECORDED",
    "CLASSIFICATION_CHANGED_RECORDED",
)
IDENTIFIER_REVIEW_STATES = ("UNKNOWN", "UNREVIEWED", "DUPLICATE", "REVIEWED")
PROVENANCE_KINDS = ("LOCALLY_RECORDED", "IMPORTED_EXTERNAL_EVIDENCE", "MIGRATED_BASELINE")
SUBJECT_KINDS = ("SITE", "LOCATION_NODE", "ASSET", "COMPOSITION_COMPONENT", "FUNCTIONAL_RELATIONSHIP")
CAPABILITY_TAGS = ("SIGN", "LIGHTING", "INSPECTABLE", "REPLACEABLE")
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V10_VERSIONED_IDENTITY",
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
    "EAV_OR_CUSTOM_ATTRIBUTES",
    "USER_AUTHORED_SCHEMA_OR_KIND",
    "SECOND_ASSET_MODEL",
    "PACKAGE_SPECIFIC_STORE_OR_WRITER",
    "INVENTORY_PARTS_PURCHASING",
    "DEPRECIATION_OR_WARRANTY",
    "AUTOMATIC_CONDITION_SCORE",
    "RECALL_POLLING_OR_MATCHING",
    "BARCODE_AS_CANONICAL_ID",
    "OPERATIONAL_DISPOSITION_OR_RETURN_TO_SERVICE",
    "INSTALLATION_AGE_OR_SAFETY_INFERENCE",
    "VERIFIED_IDENTITY_OR_LEGAL_CLAIM",
    "HOSTED_BACKEND_OR_TELEMETRY",
    "S10_RELEASE_OR_BRAND_APPROVAL",
)
REQUIRED_BEHAVIORS = (
    {"id": "CATALOG_RELEASES", "contract": "AssetSemanticCatalogReleaseV1", "requirement": "Immutable package-qualified releases expose stable semantic IDs, localized keys, capability tags, compatibility policy, and fail-closed unknown-ID admission.", "evidence": "C39-S01"},
    {"id": "KIND_DEFINITIONS", "contract": "AssetKindDefinitionV1", "requirement": "Kind definitions are bounded catalog records; structural composition and functional relationship policy remain owned by C35 and C41.", "evidence": "C39-S02"},
    {"id": "MULTI_PACKAGE_BINDING", "contract": "AssetKindBindingEventV1", "requirement": "Append-only kind and workflow-capability bindings permit zero or more compatible package releases without changing AssetID, Site, placement, or kind implicitly.", "evidence": "C39-S03"},
    {"id": "PRODUCT_ATTRIBUTES", "contract": "AssetProductIdentityV1", "requirement": "Manufacturer, model, serial, lot, part, and bounded external codes are attributed with provenance, review state, effective interval, and normalized comparison without becoming identity.", "evidence": "C39-S04"},
    {"id": "LIFECYCLE_HISTORY", "contract": "AssetLifecycleEventV1", "requirement": "Human-recorded lifecycle events and exact successor/reclassification pair references preserve immutable history and never infer operational condition or safety.", "evidence": "C39-S05"},
    {"id": "SUBJECT_SNAPSHOTS", "contract": "WorkSubjectScopeSnapshotV1", "requirement": "Frozen subject snapshots bind Site, LocationNode, Asset, component, or functional relationship to exact package and semantic releases and revisions.", "evidence": "C39-S06"},
    {"id": "SCHEMA_V10_PERSISTENCE", "contract": "AssetSemanticCatalogReleaseV1", "requirement": "Schema-v10 copy-on-write migration, writer, backup/restore, clone/fork, import/export, journal/replay, search, report, delete/Erase, compatibility, interruption, and forward-fix behavior are enrolled before first write.", "evidence": "C39-L01"},
    {"id": "LEGACY_MIGRATION", "contract": "AssetKindBindingEventV1", "requirement": "Legacy sign assets retain AssetID, artifact bytes, placement, external keys, and historic pack bindings while receiving only accepted sign semantic and package values.", "evidence": "C39-L02"},
    {"id": "STATIC_BOUNDARY", "contract": "V23-P03-C39", "requirement": "This lane is PASS_STATIC_PROVISIONAL and does not claim native, hosted, adoption, acceptance, or release evidence.", "evidence": "C39-B01"},
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV9_AssetSemanticLifecycleG01LegacySignMigrationAndPackageMatrixRemainStable",
    "testV9_AssetSemanticLifecycleA01UnknownDuplicateIdentifiersAndScopeRemainExplicit",
    "testV9_AssetSemanticLifecycleH01HostileBindingsSuccessorsAndCrossWorkspaceSubjectsFailClosed",
    "testV9_AssetSemanticLifecycleI01InterruptionRecoveryConvergesAndPinsOldReleases",
    "testV9_AssetSemanticLifecycleR01BackupRestoreSearchReportDeleteAndCompatibilityPreserveHistory",
)
SOURCE_CONTRACT_TOKENS = (CARD, "V21-P03-C39", *CONTRACT_NAMES)
EVIDENCE_CASES = (
    {"id": "C39-S01", "kind": "SOURCE_PROJECTION", "assertion": "The pinned register, V23 dossier, and inherited V21 C39 block have the exact recorded boundary bytes and digests."},
    {"id": "C39-S02", "kind": "CATALOG_CLOSURE", "assertion": "Semantic releases, kinds, capability tags, lifecycle values, provenance, identifier review states, and subject kinds are closed."},
    {"id": "C39-S03", "kind": "BINDING_MATRIX", "assertion": "The fixture covers compatible and incompatible package binding, package retirement during draft, and old-work release pinning."},
    {"id": "C39-S04", "kind": "IDENTITY_BOUNDARY", "assertion": "AssetID remains physical identity while missing, duplicate, nonunique, unknown, Unicode-collision, and externally sourced product values remain explicit attributes."},
    {"id": "C39-S05", "kind": "LIFECYCLE_PAIRING", "assertion": "Reclassification and replacement events reference exact atomic pair IDs; orphan, conflict, cyclic, and independently edited pairs fail closed."},
    {"id": "C39-S06", "kind": "SUBJECT_SCOPE", "assertion": "Subject snapshots preserve exact package/semantic revisions across Site, LocationNode, Asset, composition component, and functional relationship scopes."},
    {"id": "C39-L01", "kind": "LIFECYCLE_COVERAGE", "assertion": "Schema-v10 persistence and all required recovery, portability, privacy, search, report, delete, journal, and interruption dimensions are declared."},
    {"id": "C39-F01", "kind": "PATH_DIGEST_FENCE", "assertion": "The hydrated fence is exactly 73 paths: 58 existing and 15 new, with zero overlap against the frozen 86-path S10 reservation."},
    {"id": "C39-B01", "kind": "STATIC_BOUNDARY", "assertion": "All status flags remain false and the artifact result is PASS_STATIC_PROVISIONAL until accepted S10.6 reconciliation and later card gates."},
)

SEMANTIC_SCOPE = {
    "durableOwner": [*CONTRACT_NAMES, "PersistentSchemaV10"],
    "catalogPolicy": "IMMUTABLE_PACKAGE_QUALIFIED_RELEASES_USE_STABLE_SEMANTIC_IDS_LOCALIZATION_KEYS_CAPABILITY_TAGS_AND_FAIL_CLOSED_UNKNOWN_ID_ADMISSION",
    "identityPolicy": "ASSET_ID_REMAINS_CANONICAL_PHYSICAL_IDENTITY_AND_PRODUCT_FIELDS_ARE_BOUNDED_ATTRIBUTES_WITH_ISSUER_PROVENANCE_REVIEW_EFFECTIVE_INTERVAL_AND_NORMALIZED_COMPARISON_NEVER_UNIQUE_IDENTITY",
    "bindingPolicy": "APPEND_ONLY_KIND_AND_WORKFLOW_CAPABILITY_EVENTS_ALLOW_ZERO_OR_MORE_COMPATIBLE_PACKAGE_RELEASES_WITHOUT_IMPLICIT_IDENTITY_SITE_PLACEMENT_OR_KIND_MUTATION",
    "lifecyclePolicy": "ONLY_COMMISSIONING_NOT_RECORDED_ACTIVE_RECORDED_RETIRED_RECORDED_REPLACED_RECORDED_AND_CLASSIFICATION_CHANGED_RECORDED_EXIST_AND_REPLACEMENT_OR_RECLASSIFICATION_REFERENCE_EXACT_ATOMIC_CANONICAL_PAIR_IDS",
    "operationalBoundaryPolicy": "NO_OPERATIONAL_DISPOSITION_IN_SERVICE_RESTRICTED_OUT_OF_SERVICE_RETURNED_TO_SERVICE_RECALL_SAFETY_CONDITION_WARRANTY_INSTALLATION_OR_AGE_TRUTH_IS_INFERRED_OR_DUPLICATED",
    "scopePolicy": "IMMUTABLE_WORK_SUBJECT_SNAPSHOTS_BIND_SITE_LOCATION_ASSET_COMPOSITION_COMPONENT_OR_DECLARED_FUNCTIONAL_RELATIONSHIP_WITH_EXACT_PACKAGE_SEMANTIC_RELEASES_AND_REVISIONS",
    "ownerBoundaryPolicy": "P03_C35_SOLELY_OWNS_STRUCTURAL_COMPOSITION_POLICY_AND_P03_C41_SOLELY_OWNS_FUNCTIONAL_RELATIONSHIP_POLICY",
    "migrationPolicy": "V9_TO_V10_COPY_ON_WRITE_PRESERVES_EVERY_ASSET_ID_AND_BINDS_LEGACY_SIGN_ASSETS_TO_ACCEPTED_SIGN_SEMANTIC_KIND_AND_EXISTING_LEGACY_PACK_VALUES_WITH_NO_INVENTED_PRODUCT_INSTALLATION_OR_LIFECYCLE_FACT",
    "writerPolicy": "P02_C01_SOLE_WORKSPACE_WRITER_COMMITS_EXPECTED_REVISION_MUTATION_ID_ATOMIC_REFERENCES_DURABLE_RECEIPT_JOURNAL_AND_EFFECT_BEFORE_RECEIPT_RECOVERY",
    "fullLifecyclePolicy": "SCHEMA_MIGRATION_COMPATIBILITY_BACKUP_RESTORE_CLONE_FORK_ARCHIVE_OPEN_JSON_IMPORT_BULK_SEARCH_REBUILD_JOURNAL_REPLAY_CHECKPOINT_REPORT_DELETE_ERASE_PRIVACY_INTERRUPTION_AND_DOWNGRADE_ENROLL_EVERY_NEW_KIND_BEFORE_FIRST_WRITE",
    "historyPolicy": "RETIRED_REPLACED_PREDECESSOR_SUCCESSOR_AND_OLD_SUBJECT_PACKAGE_SEMANTIC_SNAPSHOTS_REMAIN_IMMUTABLE_AND_DELETION_NEVER_CASCADES_INTO_WORK_REPORTS_OR_SITE",
    "forbiddenPolicy": "NO_EAV_CUSTOM_ATTRIBUTES_USER_AUTHORED_KINDS_ARBITRARY_JSON_PACKAGE_TABLES_SECOND_ASSET_MODEL_STORE_WRITER_RENDERER_REGISTRY_GRAPH_VERTICAL_MIN_APP_RECALL_POLLING_INVENTORY_PURCHASING_DEPRECIATION_OR_WARRANTY",
    "localizationAccessibilityPolicy": "UNKNOWN_DUPLICATE_RETIRED_AND_REPLACED_STATES_USE_TYPED_EN_ONLY_CATALOG_KEYS_SEMANTIC_IDS_NONCOLOR_TEXT_DYNAMIC_TYPE_RTL_AND_LONG_TEXT_CONTRACTS",
    "privacyPolicy": "PRODUCT_IDENTIFIERS_ARE_PROGRESSIVELY_DISCLOSED_AND_OMITTED_FROM_CUSTOMER_SAFE_OUTPUT_UNLESS_EXPLICIT_POLICY_ALLOWS",
    "s10Policy": "EXACT_EIGHTY_SIX_PATH_RESERVATION_IS_FROZEN_AND_CARD_PATH_FENCE_HAS_ZERO_S10_OVERLAP",
    "activationPolicy": "PROVISIONAL_PRE_S10_NONRESERVED_SCHEMA_CONTRACT_LIFECYCLE_FIXTURE_AND_TEST_IMPLEMENTATION_ONLY_NATIVE_HOSTED_RESERVED_UI_ACCEPTANCE_RELEASE_AND_PHASE10_POLLING_DEFERRED_PENDING_ACCEPTED_S10_6_RECONCILIATION",
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
    completed = subprocess.run(
        ["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"],
        check=True,
        capture_output=True,
    )
    return completed.stdout


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
        return {"type": "string"}
    if isinstance(value, list):
        item_schemas = {_schema_for_value(item).__repr__(): _schema_for_value(item) for item in value}
        result: dict[str, Any] = {"type": "array", "minItems": len(value), "maxItems": len(value)}
        if item_schemas:
            result["items"] = next(iter(item_schemas.values())) if len(item_schemas) == 1 else {"anyOf": [item_schemas[key] for key in sorted(item_schemas)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "properties": {key: _schema_for_value(value[key]) for key in sorted(value)},
            "required": sorted(value),
        }
    raise TypeError(f"unsupported schema value: {type(value)!r}")


def schema_document(root: Path) -> dict[str, Any]:
    fixture = json.loads((root / FIXTURE_PATH).read_text(encoding="utf-8"))
    document = _schema_for_value(fixture)
    document.update(
        {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://assetrounds.invalid/v23/asset-semantics.schema.json",
            "title": "V23 P03 C39 Asset Semantic Corpus",
        }
    )
    return document


def _flags() -> dict[str, bool]:
    return {
        "native": False,
        "hosted": False,
        "adoption": False,
        "acceptance": False,
        "release": False,
        "nativeAcceptance": False,
        "hostedAcceptance": False,
        "adoptionEvidence": False,
        "acceptanceCredit": False,
        "releaseReadiness": False,
    }


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION,
        "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C38"],
        "allowedPathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "persistentContractSchema": "PERSISTENT_SCHEMA_V10_ASSET_SEMANTICS",
        "schemaBehaviorDelta": True,
        "migrationBehaviorDelta": True,
        "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True,
        "restoreCompatibilityRequired": True,
        "deleteCompatibilityRequired": True,
        "exportCompatibilityRequired": True,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V10_WRITE",
        "uiSurfaceDelta": True,
        "brandSurfaceDelta": True,
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _source_projection() -> dict[str, Any]:
    return {
        "registerRows": ["| 47 | <a id=\"v23-p03-c39-register\"></a>[`V23-P03-C39`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c39) | Shared asset semantics, product identity, lifecycle, multi-package binding, and frozen work-subject scope | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C38` | `EXACT_WITH_GENERATION_REBIND` |"],
        "registerSectionSHA256": REGISTER_SECTION_SHA256,
        "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
        "registerRowSHA256": REGISTER_ROW_SHA256,
        "registerRowUTF8Length": REGISTER_ROW_UTF8_LENGTH,
        "dossierSHA256": DOSSIER_SHA256,
        "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
        "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
        "inheritedV21PayloadPresent": True,
        "facetRowCount": 0,
        "canonicalRecordWriterOwnershipRowCount": 8,
        "facetManifestDigest": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
        "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001", "V23-POL-HIG-001", "V23-POL-A11Y-001", "V23-POL-L10N-001"],
        "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C39).CONTRACTS", *CONTRACT_NAMES, "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
        "journeyRefs": ["NONE"],
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "invalidationConsumers": ["V23-P03-C40", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
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


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "pathFence": list(PATH_FENCE),
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "existingPaths": list(EXISTING_PATHS),
        "newPaths": list(NEW_PATHS),
        "pathFenceDigest": FENCE_DIGEST,
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
        "s10FenceOverlapPaths": [],
    }


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "blueprintPath": AUTHORITY_REFERENCE_PATHS[0],
        "foundationPath": AUTHORITY_REFERENCE_PATHS[1],
        "sourceProjection": _source_projection(),
        "sourceTokens": list(SOURCE_CONTRACT_TOKENS),
        "requiredContractNames": list(CONTRACT_NAMES),
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
    }


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows = source_artifacts(root)
    authority_rows = authority_artifacts(root)
    return _sealed(
        {
            "schema": "V23P03C39AssetSemanticsContractV1",
            "artifact": "V23P03C39AssetSemanticsContractV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "status": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "sourceProjection": _source_projection(),
            "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
            "schemaArtifact": schema_row,
            "sourceContract": _source_contract(source_rows, authority_rows),
            "semanticScope": SEMANTIC_SCOPE,
            "requiredSemantics": {
                "contractNames": list(CONTRACT_NAMES),
                "catalogStates": list(CATALOG_STATES),
                "lifecycleStates": list(LIFECYCLE_STATES),
                "identifierReviewStates": list(IDENTIFIER_REVIEW_STATES),
                "provenanceKinds": list(PROVENANCE_KINDS),
                "subjectKinds": list(SUBJECT_KINDS),
                "capabilityTags": list(CAPABILITY_TAGS),
                "requiredBehaviors": list(REQUIRED_BEHAVIORS),
                "forbiddenClaims": list(FORBIDDEN_CLAIMS),
            },
            "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
            "pathEvidence": _path_evidence(source_rows, authority_rows),
            "evidenceIDs": list(EVIDENCE_IDS),
            "testMethods": list(TEST_METHODS),
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "priorFenceProof": PRIOR_FENCE_PROOF,
            "evidenceCases": list(EVIDENCE_CASES),
            "successor": {"cardID": "V23-P03-C40", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"},
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed(
        {
            "schema": "V23P03C39AssetSemanticsEvidenceReceiptV1",
            "artifact": "V23P03C39AssetSemanticsEvidenceReceiptV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "result": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "sourceProjection": _source_projection(),
            "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
            "sourceContractDigest": sha256_value(source_rows),
            "authorityArtifactDigest": sha256_value(authority_rows),
            "schemaArtifact": schema_row,
            "contractArtifact": contract_row,
            "evidenceIDs": list(EVIDENCE_IDS),
            "testMethods": list(TEST_METHODS),
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "priorFenceProof": PRIOR_FENCE_PROOF,
            "evidenceCases": list(EVIDENCE_CASES),
            "requiredSemanticsDigest": sha256_value(
                {
                    "contractNames": list(CONTRACT_NAMES),
                    "catalogStates": list(CATALOG_STATES),
                    "lifecycleStates": list(LIFECYCLE_STATES),
                    "identifierReviewStates": list(IDENTIFIER_REVIEW_STATES),
                    "provenanceKinds": list(PROVENANCE_KINDS),
                    "subjectKinds": list(SUBJECT_KINDS),
                    "capabilityTags": list(CAPABILITY_TAGS),
                    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
                    "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
                }
            ),
            "pathEvidence": _path_evidence(source_rows, authority_rows),
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed(
        {
            "schema": "V23P03C39BrandImpactManifestV1",
            "artifact": "V23P03C39BrandImpactManifestV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "status": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI",
            "affectedSurfacePaths": [],
            "semanticStates": ["UNKNOWN", "DUPLICATE", "RETIRED", "REPLACED", "CLASSIFICATION_CHANGED"],
            "contractArtifact": contract_row,
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "s10FenceOverlapPaths": [],
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )


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
    schema_raw = pretty(schema_document(root))
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract_raw = pretty(contract_document(root, schema_row))
    contract_row = {"path": CONTRACT_PATH, "bytes": len(contract_raw), "sha256": sha256_bytes(contract_raw)}
    source_rows = source_artifacts(root)
    authority_rows = authority_artifacts(root)
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract_row))
    evidence_row = {"path": EVIDENCE_PATH, "bytes": len(evidence_raw), "sha256": sha256_bytes(evidence_raw)}
    brand_raw = pretty(brand_document(contract_row))
    rendered = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, relative, rendered) for relative in MANIFEST_INPUT_PATHS]
    manifest = _sealed(
        {
            "schema": "V23P03C39ToolingManifestV1",
            "artifact": "V23P03C39ToolingManifestV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "result": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "baseHead": BASE_HEAD,
            "baseTree": BASE_TREE,
            "pathFence": list(PATH_FENCE),
            "fullFencePaths": list(FULL_FENCE_PATHS),
            "pathFenceDigest": FENCE_DIGEST,
            "pathFenceCount": len(PATH_FENCE),
            "allowedCreateOrReplacePaths": list(PATH_FENCE),
            "allowedDeletePaths": [],
            "allowedRenamePaths": [],
            "existingPathCount": len(EXISTING_PATHS),
            "newPathCount": len(NEW_PATHS),
            "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS),
            "sourceArtifacts": source_rows,
            "authorityArtifacts": authority_rows,
            "artifacts": manifest_rows,
            "artifactSetDigest": sha256_value(manifest_rows),
            "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "priorFenceProof": PRIOR_FENCE_PROOF,
            "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
            "s10FenceOverlapPaths": [],
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered

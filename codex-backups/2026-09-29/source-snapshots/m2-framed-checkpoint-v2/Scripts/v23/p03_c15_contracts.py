#!/usr/bin/env python3
"""Deterministic static contract and evidence builders for V23-P03-C15.

This module is deliberately data-only. It binds the hydrated coordination
authority and the exact app fence, then renders the corpus, schema, receipts,
brand boundary, and manifest with stable JSON bytes. It never performs a
native build, hosted dispatch, release action, or mutation of app data.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C15"
TITLE = "Replayable WorkPacketManifestV1 with item claim, lease, release, and handoff semantics"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 52
BASE_HEAD = "cf425681d53f5ca5f05b06895ea0badb5b340aee"
BASE_TREE = "7db980a30ce3ec4ca6af86b9f70b2e41a811355c"
CONTEXT_DIGEST = "8e0f76262c67db671706d6c7a17c46b404bb7a2470af8424321a8503045fc632"
FENCE_DIGEST = "a0b746c04bf9016ca5dd421ac95973065a066e6f53a30c347c94c747f9607308"
PREREQUISITE_DIGEST = "17bf6563fad2aa22053fef97999959179cc81e1d5072eb51ad86c1c0ba22b2e3"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
COORDINATION_HEAD = "aee42398b9c2aa239b992f3dd73399ccd3ba250b"
COORDINATION_TREE = "2ecae408776ab56c94b9cb60eafbc96ba4801862"
COORDINATION_LEDGER_DIGEST = "88ba20ade9b3fe6ad26eebef41684aca8e09f2a3988f9a995f93e1f3d6b8645b"
COORDINATION_CAS_SEQUENCE = 220
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "b721b4c36dc168323a8c26557e739fd6d36116f6e827044958ca04ecaffe3ac9"
DOSSIER_SHA256 = "53153dfb8612320a29c1a30e2212ef936a71e87eb4dae74fda885c7a37aef2b1"
DOSSIER_UTF8_LENGTH = 7091
INHERITED_V21_BLOCK_SHA256 = "5f7da0f65be5c7a0faa0a3301dd9e887369873e15cd076d45665b143a86f7b34"
INHERITED_V21_BLOCK_UTF8_LENGTH = 9042

SCHEMA_PATH = "Scripts/v23/work-packet-manifest.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C15WorkPacketManifestContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C15WorkPacketManifestEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C15BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C15-tooling-manifest.json"
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/WorkPacketManifest/V21P03C15WorkPacketManifestCorpusV1.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c15_contracts.py",
    "Scripts/v23/generate_p03_c15_contracts.py",
    "Scripts/v23/verify_p03_c15_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS


# The exact 72-path existing projection supplied by C15 hydration.
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
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
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
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
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
)

NEW_PATHS = (
    "FieldEvidenceApp/Domain/InspectionKernel/WorkPacketManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkPacketManifestPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/WorkPacket/WorkPacketManifestCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/WorkPacket/WorkPacketManifestLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_29WorkPacketManifestTests.swift",
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


def _overlap(card: str, digest: str, disposition: str, count: int) -> dict[str, Any]:
    return {"cardID": card, "fenceDigest": digest, "disposition": disposition, "overlapCount": count}


PRIOR_FENCE_OVERLAPS = (
    _overlap("V23-P00-C10", "f34d2e3ea8defd5ff7146a499b88e39c76b0a925c519bb524120a2542064d1cb", "CHECK_RUNNER_COMMAND_AND_FINALIZATION_GUARD_REPROOF_REQUIRED", 2),
    _overlap("V23-P00-C11", "560b3bd0401d0da46bcedc9f7184c8041e198db8cbe8af3011731fc0ad6cc8b1", "ERASE_CONCURRENCY_AND_LIFECYCLE_REPROOF_REQUIRED", 1),
    _overlap("V23-P01-C01", "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", "SCHEMA_SUCCESSOR_AND_MIGRATION_REPROOF_REQUIRED", 3),
    _overlap("V23-P01-C02", "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", "OWNED_FILE_RESTORE_CLONE_FORK_AND_GENERATION_REPROOF_REQUIRED", 6),
    _overlap("V23-P01-C03", "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", "COPY_ON_WRITE_MIGRATION_RECOVERY_REPROOF_REQUIRED", 6),
    _overlap("V23-P01-C04", "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", "ARCHIVE_AND_OPEN_COMPATIBILITY_REPROOF_REQUIRED", 3),
    _overlap("V23-P01-C05", "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", "CANONICAL_BACKUP_RESTORE_AND_IDENTITY_REPROOF_REQUIRED", 12),
    _overlap("V23-P01-C06", "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", "DELETE_ERASE_AND_PORTABLE_LIFECYCLE_REPROOF_REQUIRED", 23),
    _overlap("V23-P01-C07", "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", "RELEASED_DATA_AND_HISTORIC_REPORT_COMPATIBILITY_REPROOF_REQUIRED", 7),
    _overlap("V23-P02-C01", "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", "SOLE_WRITER_AND_COMMAND_REPROOF_REQUIRED", 6),
    _overlap("V23-P02-C02", "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", "MUTATION_RECEIPT_JOURNAL_AND_RECOVERY_REPROOF_REQUIRED", 29),
    _overlap("V23-P02-C03", "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", "SYNC_CLASSIFICATION_AND_CONFLICT_REPROOF_REQUIRED", 22),
    _overlap("V23-P02-C04", "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", "GENERATION_LEASE_AND_STALE_WRITER_REPROOF_REQUIRED", 6),
    _overlap("V23-P02-C05", "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", "RESUMABLE_JOB_BOUNDARY_REPROOF_REQUIRED", 9),
    _overlap("V23-P02-C06", "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", "DEVICE_TIME_AND_PROTECTED_DATA_REPROOF_REQUIRED", 2),
    _overlap("V23-P02-C07", "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", "OBSERVATION_TIME_AND_PROJECTION_REPROOF_REQUIRED", 26),
    _overlap("V23-P02-C08", "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", "SYSTEM_HEALTH_CLASSIFICATION_REPROOF_REQUIRED", 5),
    _overlap("V23-P02-C09", "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", "PERSISTENT_KIND_LIFECYCLE_COVERAGE_REPROOF_REQUIRED", 5),
    _overlap("V23-P03-C06", "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2", "COMPLETED_SNAPSHOT_IMMUTABILITY_REPROOF_REQUIRED", 6),
    _overlap("V23-P03-C07", "3f6a36f8794c159c24c26ec06506bff77a2d998df3cf04a5b8b06bb1d56e8264", "KERNEL_BACKUP_RESTORE_DELETE_ERASE_REGISTRY_REPROOF_REQUIRED", 2),
    _overlap("V23-P03-C08", "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", "PACK_LIFECYCLE_BACKUP_RESTORE_AND_DELETE_REPROOF_REQUIRED", 11),
    _overlap("V23-P03-C09", "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", "SEARCH_SCHEMA_REBUILD_AND_LIFECYCLE_REPROOF_REQUIRED", 39),
    _overlap("V23-P03-C10", "7e90b5eb871c6560b395fb487d0155a31a499009c6a2d4303b0aa668476d80f8", "PORTABLE_KERNEL_CONFORMANCE_HARNESS_REPROOF_REQUIRED", 1),
    _overlap("V23-P03-C11", "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", "JOURNAL_CHECKPOINT_AND_REPLAY_REPROOF_REQUIRED", 5),
    _overlap("V23-P03-C12", "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED", 32),
    _overlap("V23-P03-C13", "3a8af6eccec4a8842fde87c41ba665400ec2d20a8c80796c9945559b6c4c49ef", "DIRECT_PREREQUISITE_EVIDENCE_ASSURANCE_REPROOF_REQUIRED", 69),
    _overlap("V23-P03-C14", "ba02fb62b37fcf10416c474cfaa366d5a2ec8f6785ca10a581fd940b6643a2d3", "ORDERED_PREDECESSOR_SHARED_LIFECYCLE_REPROOF_REQUIRED", 71),
    _overlap("V23-P03-C16", "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED", 5),
    _overlap("V23-P03-C35", "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED", 37),
    _overlap("V23-P03-C38", "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", "ACCOUNTABILITY_ACTOR_QUALIFICATION_SNAPSHOT_REPROOF_REQUIRED", 48),
    _overlap("V23-P03-C39", "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2", "ASSET_SEMANTICS_SUBJECT_PACKAGE_AND_LIFECYCLE_REPROOF_REQUIRED", 48),
    _overlap("V23-P03-C40", "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397", "DIRECT_PREREQUISITE_AUTHORITY_AND_SHARED_LIFECYCLE_REPROOF_REQUIRED", 60),
    _overlap("V23-P03-C41", "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000", "DIRECT_PREREQUISITE_FUNCTIONAL_SNAPSHOT_REPROOF_REQUIRED", 69),
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 52,
    "priorOwnedPathCount": 869,
    "overlapCount": 676,
    "authorizedOverlapCount": 676,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}


CONTRACT_NAMES = (
    "WorkPacketManifestV1",
    "WorkItemClaimV1",
    "WorkLeaseV1",
    "WorkReleaseV1",
    "WorkHandoffV1",
)
SUBJECT_KINDS = ("WORK_PACKET_MANIFEST", "WORK_PACKET_ITEM", "WORK_PACKET_RESULT")
ITEM_KINDS = ("INSPECTION", "CORRECTIVE_ACTION", "REVIEW_CHANGE_REQUEST", "OPERATIONAL_RECHECK")
CREATION_BASES = ("EXPLICIT_LOCAL_SELECTION", "DETERMINISTIC_DUE_PROJECTION", "RECORDED_REVIEW_DISPOSITION")
RELEASE_REASONS = ("COMPLETED", "DELIBERATELY_RELEASED", "LEASE_EXPIRED", "HANDOFF", "RECLAIMED")
REPLAY_DISPOSITIONS = ("APPLY", "IDEMPOTENT_REPLAY", "QUARANTINE_DIVERGENT_BYTES")
CONFLICT_KINDS = ("SIMULTANEOUS_CLAIM", "STALE_RESULT_REVISION", "EXPIRED_LEASE_RESULT", "DIVERGENT_SAME_IDENTITY")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV9_WorkPacketManifestG01ClaimLeaseReleaseHandoffAndReplay",
    "testV9_WorkPacketManifestA01UnclaimedReleaseAndExpiredLeaseReclaim",
    "testV9_WorkPacketManifestH01DuplicateDivergentStaleAndSimultaneousFailClosed",
    "testV9_WorkPacketManifestI01InterruptedMutationProjectionAndReplayRecover",
    "testV9_WorkPacketManifestR01BackupRestoreCloneForkDeleteEraseSearchReportAndHistoryPreserve",
)
SOURCE_CONTRACT_TOKENS = (CARD, "V21-P03-C15", *CONTRACT_NAMES)

LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V15_RECORDS14_VERSIONED_IDENTITY",
    "WRITER_COMMAND_QUERY_EXPECTED_REVISION_MUTATION_ID",
    "V14_TO_V15_COPY_ON_WRITE_MIGRATION",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK_GENERATION",
    "IMPORT_EXPORT_METADATA_ONLY_PREVIEW",
    "JOURNAL_REPLAY_CHECKPOINT",
    "DELETE_ERASE_RETENTION",
    "LOCAL_SEARCH_REBUILD",
    "REPORT_SNAPSHOT_OPEN_JSON",
    "LOCALIZATION_ACCESSIBILITY_PRIVACY",
    "INTERRUPTION_IDEMPOTENT_RECEIPTS",
    "DOWNGRADE_FORWARD_FIX_AFTER_FIRST_V15_WRITE",
)
FORBIDDEN_CLAIMS = (
    "ACCOUNT_OR_AUTHENTICATED_IDENTITY",
    "CLOUD_PROVIDER_OR_REMOTE_STORAGE",
    "DELIVERY_OR_TRANSMISSION_OUTBOX",
    "CMMS_WORK_ORDER_OR_INVENTORY",
    "AI_DIAGNOSIS_OR_AUTOMATIC_PASS_FAIL",
    "LEGAL_SIGNATURE_OR_NONREPUDIATION",
    "SECURITY_CERTIFICATION_OR_VERIFIED_IDENTITY",
    "FINALIZATION_OR_RELEASE_APPROVAL_PRODUCER",
    "NATIVE_IPAD_OR_SECOND_UI_SURFACE",
    "CUSTOMER_DATA_TELEMETRY_OR_MARKETING",
    "SECOND_STORE_OR_SECOND_CANONICAL_WRITER",
)


TEST_CORPUS_SHAPE: dict[str, Any] = {
    "schema": "V21P03C15WorkPacketManifestCorpusV1",
    "schemaVersion": 1,
    "cardID": CARD,
    "ordinal": REGISTER_ORDINAL,
    "phase": "P03",
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "requiredContractNames": list(CONTRACT_NAMES),
    "subjectKinds": list(SUBJECT_KINDS),
    "itemKinds": list(ITEM_KINDS),
    "creationBases": list(CREATION_BASES),
    "releaseReasons": list(RELEASE_REASONS),
    "replayDispositions": list(REPLAY_DISPOSITIONS),
    "conflictKinds": list(CONFLICT_KINDS),
    "persistence": {
        "schemaRelease": "PERSISTENT_SCHEMA_V15_WORK_PACKET_COORDINATION",
        "recordSchemaVersion": 14,
        "recordsSchemaVersion": 14,
        "predecessorSchemaVersion": 14,
        "predecessorRecordSchemaVersion": 13,
        "migration": "EXACT_V14_TO_V15_COPY_ON_WRITE",
        "canonicalWriter": "V23-P02-C01",
        "lifecycleOwner": CARD,
        "firstWriteEnrolled": True,
        "compatibilityRequired": True,
        "backupRestoreRequired": True,
        "deleteEraseRequired": True,
        "exportImportPreviewRequired": True,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V15_WRITE",
        "persistedFamilies": list(CONTRACT_NAMES),
        "durableRowCount": 5,
        "currentProjectionRows": 0,
        "currentProjectionRowCount": 0,
        "secondStore": False,
        "secondWriter": False,
        "accountStore": False,
        "cloudStore": False,
        "deliveryOutbox": False,
        "descriptorEventOnlyPersistence": False,
        "nonPersistentFamilies": ["WorkPacketProjectionV1", "WorkPacketReviewExceptionV1"],
        "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY",
        "snapshotBinding": "COMPLETED_ACTIVITY_OR_REPORT_SNAPSHOT_EXACT_SUBJECT_DIGEST_REQUIRED",
        "purposeBinding": "WORK_PACKET_ITEM_AND_LOCAL_ACTOR_SCOPE_REQUIRED",
        "supersessionAndVoid": "APPEND_ONLY_IMMUTABLE_HISTORY",
        "legacyRowsCreated": 0,
    },
    "manifestCases": [
        {
            "id": "manifest-synthetic-1",
            "workspaceID": "workspace-synthetic-1",
            "manifestID": "manifest-synthetic-1",
            "packetID": "packet-synthetic-1",
            "packetVersion": 1,
            "items": ["item-inspection-1", "item-recheck-1"],
            "packageReleases": ["release-synthetic-1"],
            "creationBasis": "EXPLICIT_LOCAL_SELECTION",
            "immutable": True,
            "boundSubjectDigest": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }
    ],
    "claimCases": [
        {"id": "claim-first", "sequence": 1, "supersedes": None, "immutable": True},
        {"id": "claim-reclaim", "sequence": 2, "supersedes": "claim-first", "immutable": True},
    ],
    "leaseCases": [
        {"id": "lease-active", "sequence": 1, "expired": False, "immutable": True},
        {"id": "lease-expired", "sequence": 2, "expired": True, "immutable": True},
    ],
    "releaseCases": [
        {"id": "release-completed", "reason": "COMPLETED", "immutable": True},
        {"id": "release-deliberate", "reason": "DELIBERATELY_RELEASED", "immutable": True},
        {"id": "release-expired", "reason": "LEASE_EXPIRED", "immutable": True},
        {"id": "release-handoff", "reason": "HANDOFF", "immutable": True},
        {"id": "release-reclaimed", "reason": "RECLAIMED", "immutable": True},
    ],
    "handoffCases": [
        {"id": "handoff-immutable-result-links", "fromHolder": "actor-a", "toHolder": "actor-b", "resultLinksImmutable": True}
    ],
    "replayCases": [
        {"id": "replay-apply", "disposition": "APPLY"},
        {"id": "replay-idempotent", "disposition": "IDEMPOTENT_REPLAY"},
        {"id": "replay-divergent", "disposition": "QUARANTINE_DIVERGENT_BYTES"},
    ],
    "conflictCases": [{"id": kind.lower().replace("_", "-"), "kind": kind, "preserveAllWorkProducts": True} for kind in CONFLICT_KINDS],
    "currentProjectionRows": [],
    "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY",
    "projectionRebuild": {"deterministic": True, "rebuildFromOrderedHistory": True, "rows": 0},
    "lifecycleCoverage": [{"dimension": dimension, "enrolledBeforeFirstWrite": True, "disposition": "EXPLICIT_STATIC_CONTRACT"} for dimension in LIFECYCLE_DIMENSIONS],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED"} for case_id in (
        "cross-workspace-manifest", "cross-workspace-item", "duplicate-packet", "divergent-same-id",
        "stale-expected-revision", "simultaneous-claim", "expired-lease", "reordered-history",
        "missing-result", "second-store", "second-writer", "account-producer", "cloud-producer",
        "delivery-outbox", "cmms-work-order", "ai-diagnosis", "legal-signature",
        "nonrepudiation", "finalization-producer", "current-projection-row",
    )],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "PRIOR_ACCEPTED_REVISION_OR_NO_PARTIAL_AUTHORITY"} for case_id in (
        "migration-boundary", "mutation-bundle", "claim-write", "lease-write", "release-write",
        "handoff-write", "projection-rebuild", "backup-export", "restore-replace", "delete",
        "erase", "journal-replay", "search-rebuild", "report-open-json", "localization-render",
    )],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "RECOVER_EFFECT_RECEIPT_AND_HISTORY"} for case_id in (
        "backup-restore", "clone", "fork", "forward-fix", "delete", "erase", "report-snapshot",
        "search-rebuild", "journal-replay", "replay", "immutable-history",
    )],
    "claims": {claim: False for claim in (*FORBIDDEN_CLAIMS, "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit")},
}

# Keep the richer internal corpus available to callers that want lifecycle
# cases, while the checked-in V21 fixture shape remains the compact test-lane
# projection owned by the C15 test work.
CORPUS = TEST_CORPUS_SHAPE
PERSISTENCE = {
    "schemaRelease": "PERSISTENT_SCHEMA_V15_WORK_PACKET_COORDINATION",
    "recordSchemaVersion": 14,
    "recordsSchemaVersion": 14,
    "predecessorSchemaVersion": 14,
    "predecessorRecordSchemaVersion": 13,
    "migration": "EXACT_V14_TO_V15_COPY_ON_WRITE",
    "canonicalWriter": "V23-P02-C01",
    "lifecycleOwner": CARD,
    "firstWriteEnrolled": True,
    "compatibilityRequired": True,
    "backupRestoreRequired": True,
    "deleteEraseRequired": True,
    "exportImportPreviewRequired": True,
    "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V15_WRITE",
    "persistedFamilies": list(CONTRACT_NAMES),
    "durableRowCount": 5,
    "currentProjectionRows": 0,
    "currentProjectionRowCount": 0,
    "secondStore": False,
    "secondWriter": False,
    "accountStore": False,
    "cloudStore": False,
    "deliveryOutbox": False,
    "descriptorEventOnlyPersistence": False,
    "nonPersistentFamilies": ["WorkPacketProjectionV1", "WorkPacketReviewExceptionV1"],
    "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY",
    "snapshotBinding": "COMPLETED_ACTIVITY_OR_REPORT_SNAPSHOT_EXACT_SUBJECT_DIGEST_REQUIRED",
    "purposeBinding": "WORK_PACKET_ITEM_AND_LOCAL_ACTOR_SCOPE_REQUIRED",
    "supersessionAndVoid": "APPEND_ONLY_IMMUTABLE_HISTORY",
    "legacyRowsCreated": 0,
}
TEST_CORPUS_SHAPE = {
    "cardID": CARD,
    "ordinal": REGISTER_ORDINAL,
    "phase": "P03",
    "itemKinds": list(ITEM_KINDS),
    "creationBases": list(CREATION_BASES),
    "releaseReasons": list(RELEASE_REASONS),
    "conflictKinds": list(CONFLICT_KINDS),
    "coverage": ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"],
    "evidenceIDs": ["G01", "A01", "H01", "I01", "R01"],
    "boundaryRefs": ["V23-P03-C14", "V23-P03-C38"],
    "integrationSurfaces": ["backup", "restore", "import", "delete", "erase", "migration", "search", "report", "replay", "clone", "fork"],
    "persistentModelCount": 58,
    "recordsSchemaVersion": 14,
    "provisionalFlags": {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False},
}

SEMANTIC_SCOPE = {
    "durableOwner": [*CONTRACT_NAMES, "PersistentSchemaV15"],
    "manifestPolicy": "IMMUTABLE_BOUNDED_PACKET_WORKSPACE_ITEM_EXPECTED_REVISION_PACKAGE_POLICY_EVIDENCE_CREATION_BASIS_AND_DIGEST",
    "coordinationPolicy": "APPEND_ONLY_ITEM_CLAIM_LEASE_SEQUENCE_EXPIRY_RELEASE_HANDOFF_AND_IMMUTABLE_RESULT_LINKS",
    "actorPolicy": "C38_LOCAL_ACTOR_SNAPSHOT_REFERENCE_ONLY_WITH_NO_ACCOUNT_AUTHORIZATION_DISPATCH_OR_VERIFIED_IDENTITY_CLAIM",
    "collisionPolicy": "DIVERGENT_SAME_ID_STALE_REVISION_AND_SIMULTANEOUS_CLAIM_PRESERVE_ALL_WORK_PRODUCTS_AND_CREATE_ONE_EXPLICIT_REVIEW_EXCEPTION",
    "writerPolicy": "SOLE_WORKSPACE_WRITER_EXPECTED_REVISION_MUTATION_ID_ATOMIC_DURABLE_RECEIPT_JOURNAL_AND_EFFECT_BEFORE_RECEIPT_RECOVERY",
    "fullLifecyclePolicy": "V15_SCHEMA_RECORDS14_ZERO_INVENTION_MIGRATION_BACKUP_RESTORE_IMPORT_EXPORT_CLONE_FORK_DELETE_ERASE_REPORT_SEARCH_JOURNAL_REPLAY_LOCALIZATION_ACCESSIBILITY_PRIVACY_INTERRUPTION_AND_IDEMPOTENCY_ENROLLED_BEFORE_FIRST_WRITE",
    "forbiddenPolicy": "NO_ACCOUNTS_AUTH_RBAC_REMOTE_TRANSPORT_PROVIDER_DELIVERY_CMMS_AI_COMPLIANCE_LEGAL_NONREPUDIATION_SIGNING_UPLOAD_SUBMISSION_OR_S10_FINALIZATION_PRODUCER",
    "s10Policy": "EXACT_EIGHTY_SIX_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

REQUIRED_BEHAVIORS = (
    {"id": "C15-S01", "contract": "WorkPacketManifestV1", "requirement": "A bounded manifest freezes workspace, packet version, item expected revisions, package releases, creation basis, and canonical digest.", "evidence": "V23-P03-C15-G01"},
    {"id": "C15-S02", "contract": "WorkItemClaimV1", "requirement": "Claims are append-only, sequence-bound, actor-scoped, and stale or simultaneous claims fail closed.", "evidence": "V23-P03-C15-G01"},
    {"id": "C15-S03", "contract": "WorkLeaseV1", "requirement": "Leases have bounded expiry, immutable successor lineage, and expired result handling.", "evidence": "V23-P03-C15-A01"},
    {"id": "C15-S04", "contract": "WorkReleaseV1", "requirement": "Release reasons and immutable result links preserve completed, deliberate, expired, handoff, and reclaimed outcomes.", "evidence": "V23-P03-C15-G01"},
    {"id": "C15-S05", "contract": "WorkHandoffV1", "requirement": "Handoffs bind distinct local holders and preserve immutable result links without identity or delivery claims.", "evidence": "V23-P03-C15-R01"},
    {"id": "C15-L01", "contract": "PersistentSchemaV15", "requirement": "Records schema 14 uses exact V14-to-V15 copy-on-write migration with compatibility and recovery.", "evidence": "V23-P03-C15-I01"},
    {"id": "C15-L02", "contract": CARD, "requirement": "Backup/restore, clone/fork, import/export preview, journal/replay, search, report, delete/Erase, localization, accessibility, privacy, downgrade, and interruption are explicit before first write.", "evidence": "V23-P03-C15-R01"},
    {"id": "C15-B01", "contract": CARD, "requirement": "Static provisional tooling makes no native, hosted, adoption, acceptance, release, or credit claim.", "evidence": "V23-P03-C15-H01"},
)

EVIDENCE_CASES = (
    {"id": "V23-P03-C15-G01", "kind": "CLAIM_LEASE_RELEASE_HANDOFF_MATRIX", "assertion": "Synthetic manifests, claims, bounded leases, release reasons, handoffs, result links, and replay outcomes cover the golden path."},
    {"id": "V23-P03-C15-A01", "kind": "RECLAIM_AND_EXPIRY_ALTERNATES", "assertion": "Unclaimed release, expired lease, deliberate release, and reclaim alternatives remain immutable and local-only."},
    {"id": "V23-P03-C15-H01", "kind": "HOSTILE_BOUNDARY", "assertion": "Cross-workspace, duplicate/divergent identity, stale revision, simultaneous claim, reordered history, missing result, current projection, and prohibited producer attempts fail closed."},
    {"id": "V23-P03-C15-I01", "kind": "INTERRUPTION_BOUNDARY", "assertion": "Schema migration, writer mutation, claim/lease/release/handoff, projection, backup/restore, delete/Erase, and replay interruption retains prior authority or one complete effect/receipt."},
    {"id": "V23-P03-C15-R01", "kind": "RECOVERY_BOUNDARY", "assertion": "Backup/restore, clone/fork, forward-fix, journal/replay, search rebuild, report open JSON, delete/Erase, and immutable history recovery reproduce typed state."},
)

SOURCE_PROJECTION = {
    "registerRows": ["| 52 | <a id=\x22v23-p03-c15-register\x22></a>[\x60V23-P03-C15\x60](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c15) | Replayable WorkPacketManifestV1 with item claim, lease, release, and handoff semantics | \x60IMPLEMENT_NOW\x60 | \x60NOT_STARTED\x60 | \x60V23-P03-C38\x60 | \x60EXACT_WITH_GENERATION_REBIND\x60 |"],
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
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C15).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
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

DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 1,
    "predecessors": [{
        "cardID": "V23-P03-C38",
        "attemptID": 1,
        "candidateHead": "f612cc70d8962a4ace80cd231b1079cc53240ec4",
        "candidateTree": "4a7340b1552a9e96332f3b709d45ac43a34f01aa",
        "contextDigest": "713964ef5d381dd4261950d11035a5c20ade1decdf615ecdbd39e1ab7953486d",
        "pathFenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4",
        "verificationReceiptDigest": "250094a8d61d5a1c762de3aa6aed2a927deddc72d9a8349dedf476d5c08d74c7",
        "checkpointDigest": "798bc7539aa29f305e5cf460acb1065c7c3691bf60fba0d63e6b542c314ebe5b",
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C38_HEAD",
    }],
    "canonicalRelationPreserved": True,
    "nonreleaseSpecialEdgeApplied": False,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "nativeCompileRan": False,
    "physicalLockedState": "REQUIRED_PENDING_OWNER",
    "acceptanceCredit": False,
    "releaseCredit": False,
    "createdAt": "2026-08-28T03:54:02Z",
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}
ORDERING_AUTHORITY = {
    "cardID": "NONE",
    "disposition": "NO_SEPARATE_ORDERING_AUTHORITY_DIRECT_C38_ONLY",
    "directPrerequisiteCardID": "V23-P03-C38",
    "directPrerequisiteHead": "f612cc70d8962a4ace80cd231b1079cc53240ec4",
    "directPrerequisiteFenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4",
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
    result: list[dict[str, Any]] = []
    for path in SOURCE_REFERENCE_PATHS:
        raw = _git_blob(root, path)
        result.append({"path": path, "source": "BASE_HEAD_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return result


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for path in AUTHORITY_REFERENCE_PATHS:
        raw = _git_blob(root, path)
        result.append({"path": path, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return result


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
    raise TypeError(type(value))


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(TEST_CORPUS_SHAPE)
    document.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/work-packet-manifest.schema.json",
        "title": "V23 P03 C15 Work Packet Manifest Corpus",
    })
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
        "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C38"],
        "orderingAuthorityCards": [],
        "allowedPathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "persistentContractSchema": PERSISTENCE["schemaRelease"],
        "recordSchemaVersion": 14,
        "recordsSchemaVersion": 14,
        "durableRowCount": 5,
        "currentProjectionRowCount": 0,
        "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY",
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
        "downgradeDisposition": PERSISTENCE["downgrade"],
        "uiSurfaceDelta": False,
        "brandSurfaceDelta": False,
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
        "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "toolPaths": list(TOOL_PATHS),
    }


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "blueprintPath": AUTHORITY_REFERENCE_PATHS[0],
        "foundationPath": AUTHORITY_REFERENCE_PATHS[1],
        "sourceProjection": SOURCE_PROJECTION,
        "sourceTokens": list(SOURCE_CONTRACT_TOKENS),
        "requiredContractNames": list(CONTRACT_NAMES),
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "corpusPath": FIXTURE_PATH,
        "corpusAvailability": "TEST_LANE_COORDINATED",
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
    }


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    required_semantics = {
        "contractNames": list(CONTRACT_NAMES),
        "subjectKinds": list(SUBJECT_KINDS),
        "itemKinds": list(ITEM_KINDS),
        "creationBases": list(CREATION_BASES),
        "releaseReasons": list(RELEASE_REASONS),
        "replayDispositions": list(REPLAY_DISPOSITIONS),
        "conflictKinds": list(CONFLICT_KINDS),
        "requiredBehaviors": list(REQUIRED_BEHAVIORS),
        "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    }
    return _sealed({
        "schema": "V23P03C15WorkPacketManifestContractV1",
        "artifact": "V23P03C15WorkPacketManifestContractV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "orderingAuthority": ORDERING_AUTHORITY,
        "schemaArtifact": schema_row,
        "sourceContract": _source_contract(source_rows, authority_rows),
        "semanticScope": SEMANTIC_SCOPE,
        "requiredSemantics": required_semantics,
        "corpusShape": TEST_CORPUS_SHAPE,
        "persistenceBoundary": PERSISTENCE,
        "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
        "pathEvidence": _path_evidence(source_rows, authority_rows),
        "evidenceIDs": list(EVIDENCE_IDS),
        "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "priorFenceProof": PRIOR_FENCE_PROOF,
        "evidenceCases": list(EVIDENCE_CASES),
        "successor": {"cardID": "V23-P03-C16", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"},
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
    })


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {
        "contractNames": list(CONTRACT_NAMES),
        "itemKinds": list(ITEM_KINDS),
        "creationBases": list(CREATION_BASES),
        "releaseReasons": list(RELEASE_REASONS),
        "replayDispositions": list(REPLAY_DISPOSITIONS),
        "conflictKinds": list(CONFLICT_KINDS),
        "requiredBehaviors": list(REQUIRED_BEHAVIORS),
        "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
    }
    return _sealed({
        "schema": "V23P03C15WorkPacketManifestEvidenceReceiptV1",
        "artifact": "V23P03C15WorkPacketManifestEvidenceReceiptV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "orderingAuthority": ORDERING_AUTHORITY,
        "sourceContractDigest": sha256_value(source_rows),
        "authorityArtifactDigest": sha256_value(authority_rows),
        "schemaArtifact": schema_row,
        "contractArtifact": contract_row,
        "evidenceIDs": list(EVIDENCE_IDS),
        "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "priorFenceProof": PRIOR_FENCE_PROOF,
        "evidenceCases": list(EVIDENCE_CASES),
        "requiredSemanticsDigest": sha256_value(semantics),
        "corpusShapeDigest": sha256_value(TEST_CORPUS_SHAPE),
        "persistenceBoundary": PERSISTENCE,
        "pathEvidence": _path_evidence(source_rows, authority_rows),
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
    })


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C15BrandImpactManifestV1",
        "artifact": "V23P03C15BrandImpactManifestV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI",
        "affectedSurfacePaths": [],
        "semanticStates": list(ITEM_KINDS) + list(RELEASE_REASONS),
        "contractArtifact": contract_row,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "s10FenceOverlapPaths": [],
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
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
    rendered = {
        SCHEMA_PATH: schema_raw,
        CONTRACT_PATH: contract_raw,
        EVIDENCE_PATH: evidence_raw,
        BRAND_PATH: brand_raw,
    }
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "schema": "V23P03C15ToolingManifestV1",
        "artifact": "V23P03C15ToolingManifestV1",
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
        "manifestInputCount": len(MANIFEST_INPUT_PATHS),
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
        "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "orderingAuthority": ORDERING_AUTHORITY,
        "persistenceBoundary": PERSISTENCE,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "priorFenceProof": PRIOR_FENCE_PROOF,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "s10FenceOverlapPaths": [],
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered

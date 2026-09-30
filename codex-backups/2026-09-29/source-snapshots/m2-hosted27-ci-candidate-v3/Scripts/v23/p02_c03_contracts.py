#!/usr/bin/env python3
"""Deterministic provisional contracts for V23-P02-C03."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P02-C03"
APP_BASE_HEAD = "e05839a52a93a367cf4b118974a45db0d47182d0"
APP_BASE_TREE = "49dc23d51ddb18d1752e97c6820ec918b27aefca"
COORDINATION_HEAD = "e0a662ca9f050b03c3f04439d3083c83b6bb89b9"
COORDINATION_TREE = "cb77483ead8b0bb3a38a2a35afdf8dd0c5ea6b71"
COORDINATION_CAS_SEQUENCE = 92
COORDINATION_LEDGER_DIGEST = "ccf99b6769d804d48277d2e24f7bbaef2057452d019d482cac63cb1512e199db"
HYDRATION_PROJECTION_DIGEST = "5cdfc8faf30aeea2ccd9f021fe1b655b6e8e801278cf19d16ee3e996047cdaca"
CONTEXT_DIGEST = "977fa96c1c91515720786d629fe2ca50cec87d544653171811f1bb4430138426"
FENCE_DIGEST = "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3"
PREREQUISITE_DIGEST = "213b125f708006475ab59e23d99a424e8b767c6efcc3808d167a25012f8af971"
TRANSITION_DIGEST = "0755effff93435a3771fc797bbe9228868dbcff78c9039b71ef7b1f91f5af2e6"
REGISTER_ROW_DIGEST = "2de00be32e26c5e366d28707f2323f3054f873aa95f15402bc7b671ab8a40188"
DOSSIER_DIGEST = "19d5bdf991e30ad2bc9d9533ce7236aeb4a813e6c8ad576f916f984be4997eb9"
INHERITED_DIGEST = "457ff9a99e9541d4e7590b946bafa8e0efc29129d65a21bfdf912a2e6455cadb"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
OVERRIDE_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"

GENERATOR_VERSION = "p02-c03-contracts-v1"
GENERATOR_SEED = 230203

CONTRACT_SCRIPT = "Scripts/v23/p02_c03_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c03_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c03_contracts.py"
REGISTRY_SCHEMA = "Scripts/v23/sync-classification-registry.schema.json"
POLICY_SCHEMA = "Scripts/v23/replication-policy-matrix.schema.json"
CONFLICT_SCHEMA = "Scripts/v23/conflict-policy-registry.schema.json"
CORPUS_SCHEMA = "Scripts/v23/conflict-resolution-corpus.schema.json"
REGISTRY_DOC = "docs/design/v23/tooling/V23P02C03SyncClassificationRegistryV1.json"
POLICY_DOC = "docs/design/v23/tooling/V23P02C03ReplicationPolicyMatrixV1.json"
CONFLICT_DOC = "docs/design/v23/tooling/V23P02C03ConflictPolicyRegistryV1.json"
CORPUS_DOC = "docs/design/v23/tooling/V23P02C03ConflictResolutionCorpusManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C03-tooling-manifest.json"

SOURCE_PATHS = [
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIntentV1.swift",
    "FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/RestoreIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/FinalizationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Domain/Mutation/SemanticReversalContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/MutationPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/MetricKitDiagnosticsAdapter.swift",
    "FieldEvidenceApp/Infrastructure/Commerce/EntitlementStore.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/Replication/SyncClassificationRegistryV1.swift",
    "FieldEvidenceApp/Domain/Replication/ReplicationPolicyV1.swift",
    "FieldEvidenceApp/Domain/Replication/ConflictPolicyV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/ReplicationPolicy/V21P02C03ReplicationConflictPolicyCorpusV1.json",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT,
    REGISTRY_SCHEMA, POLICY_SCHEMA, CONFLICT_SCHEMA, CORPUS_SCHEMA,
    REGISTRY_DOC, POLICY_DOC, CONFLICT_DOC, CORPUS_DOC, MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = TOOL_PATHS[3:]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV10_03G01CatalogCompletenessAndLifecycleRouting",
    "testV10_03A01SixRuleMatrixAndPermutationIdentity",
    "testV10_03H01UnknownLimitsPrivacyDependencyLeakAndCollisionRejection",
    "testV10_03I01NamedInputsDeferredAndInterruptionBoundaries",
    "testV10_03R01FrozenBasisRelaunchIdempotencyAndLateCompetitor",
]
CLASSIFICATIONS = ["REPLICATED", "LOCAL_ONLY", "DERIVED_REBUILDABLE", "CONTENT_BLOB", "PRIVATE_DEVICE_ONLY"]
POLICY_AXES = ["authority", "persistence", "transport", "bootstrap", "privacy", "retention", "codecVersion", "maximumSize", "dependency", "filesystemBackup", "semanticBackup", "portableExport", "delete", "erase"]
CONFLICT_RULES = ["IMMUTABLE_VERSION", "STABLE_ID_APPEND_UNION", "EXACT_REVISION_MANUAL", "DELETE_WINS", "DERIVED_REBUILD", "LOCAL_ONLY"]
PERSISTENT_MODELS = ["Asset", "DeletionLedgerRow", "EntityMutationRevisionRow", "EvidenceFile", "Issue", "MutationQuarantineRow", "MutationReceiptRow", "Packet", "PersistentSchemaReleaseMarker", "Report", "Site", "WorkflowRecord", "WorkspaceMutationStateRow"]
OWNED_FILE_KINDS = ["cache", "commerceEntitlementCache", "database", "databaseSHM", "databaseWAL", "diagnostics", "durableDirectory", "generationPointer", "generationPointerTemporary", "journal", "journalTemporary", "mediaOriginal", "mediaThumbnail", "reportPDF", "reportSnapshot", "restoreStaging", "scratch", "stagingDirectory", "stagingFile", "temporaryFile"]
PERSISTENT_MODEL_GROUPS = {
    "replicatedDeleteWins": ["DeletionLedgerRow"],
    "replicatedAppendUnion": ["MutationReceiptRow"],
    "derivedRebuildable": ["EntityMutationRevisionRow"],
    "localOnly": ["MutationQuarantineRow", "PersistentSchemaReleaseMarker", "WorkspaceMutationStateRow"],
    "replicatedExactRevision": ["Asset", "EvidenceFile", "Issue", "Packet", "Report", "Site", "WorkflowRecord"],
}
OWNED_FILE_GROUPS = {
    "contentBlob": ["mediaOriginal", "reportPDF", "reportSnapshot"],
    "derivedRebuildable": ["cache", "mediaThumbnail", "scratch"],
    "privateDeviceOnly": ["commerceEntitlementCache", "diagnostics"],
    "localOnly": ["database", "databaseSHM", "databaseWAL", "durableDirectory", "generationPointer", "generationPointerTemporary", "journal", "journalTemporary", "restoreStaging", "stagingDirectory", "stagingFile", "temporaryFile"],
}
PORTABLE_CONTENT_PROJECTIONS = ["DeletionLedgerV2", "MutationHistorySnapshotV1", "ReportSnapshotV1", "StreamingArchiveIndexV1", "V4BackupAssetDTO", "V4BackupEvidenceFileDTO", "V4BackupIssueDTO", "V4BackupManifestV1", "V4BackupPacketDTO", "V4BackupRecordsV1", "V4BackupReportDTO", "V4BackupSiteDTO", "V4BackupWorkflowRecordDTO"]
DERIVED_INDEXES = ["ReportHistoryIndexValue", "reportHistoryChronology"]
DERIVED_PROJECTIONS = ["EntityMutationRevisionSemanticV1", "MutationQuarantineSemanticV1", "MutationReceiptSemanticV1", "StoreSemanticEnvelopeV3", "StoreSemanticEnvelopeV4", "WorkspaceMutationStateSemanticV1", "entityMutationRevision", "workspaceMutationState"]
JOURNAL_RECOVERY = ["CurrentGenerationPointerV2", "CurrentGenerationPointerV3", "DeletionIntentV1", "EraseIntentV1", "ErasePreparationV2", "FinalizationIntentV1", "MutationEnvelopeV1", "MutationHistoryQuarantineRecordV1", "MutationReceiptV1", "PreparedMigrationEnvelopeV1", "RestoreIntentV1", "ReversalBasisV1", "SemanticReversalReceiptV1", "StoreGenerationManifestV1", "StoreMigrationJournalV1", "deletionIntent", "eraseIntent", "finalizationIntent", "mutationReceipt", "restoreIntent", "storeMigration"]
DIAGNOSTICS = ["DiagnosticExportV1", "DiagnosticsLogEvent", "DiagnosticsV1", "LaunchTimeMillisecondsV1", "MetricKitSummaryV1", "PurchaseResultHistogram", "diagnosticCounters"]
PROHIBITED_FIELDS = ["accountID", "authenticatedUserID", "inbox", "outbox", "providerID", "remoteAcknowledgement", "serverCursor", "serverRevision", "tenantID", "vectorClock", "accessToken", "serviceCredential", "secretMaterial"]


class ContractError(ValueError):
    pass


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False, "hostedDispatchRan": False,
        "physicalEvidenceComplete": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False,
        "releaseReady": False, "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": 23,
        "title": "SyncClassificationRegistryV1, ReplicationPolicyV1, and ConflictPolicyV1 completeness gates",
        "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND", "lineageSource": "V21-P02-C03",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion", "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD, "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST, "foundationRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST, "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST, "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DIGEST, "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_DIGEST,
        "directPrerequisites": ["V23-P02-C02"], "invalidationConsumers": ["V23-P02-C04"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema_name: str) -> dict[str, Any]:
    return {"schema": schema_name, "schemaVersion": 1, "cardID": CARD, "authority": authority()}


def registry_contract() -> dict[str, Any]:
    return seal({
        **base("SyncClassificationRegistryV1"),
        "schemaID": "SYNC_REPLICATION_CONFLICT_POLICY_V1",
        "classifications": CLASSIFICATIONS, "classificationSetClosed": True,
        "subjectCategories": ["PERSISTENT_MODEL", "OWNED_FILE_CLASS", "JOURNAL", "INDEX", "PROJECTION", "DIAGNOSTIC", "SECRET"],
        "completeness": {
            "everyCurrentSubjectExactlyOnce": True, "defaultClassificationAllowed": False,
            "unknownOrDuplicateSubject": "FAIL_CLOSED", "maximumRegistrationCount": 128,
            "registrationCount": 43,
            "persistentModels": PERSISTENT_MODELS, "persistentModelCount": 13,
            "ownedFileKinds": OWNED_FILE_KINDS, "ownedFileKindCount": 20,
            "portableContentProjections": PORTABLE_CONTENT_PROJECTIONS,
            "derivedIndexes": DERIVED_INDEXES, "derivedProjections": DERIVED_PROJECTIONS,
            "journalRecoveryKinds": JOURNAL_RECOVERY,
            "diagnosticKinds": DIAGNOSTICS, "secretKinds": [],
            "categoryCounts": {"DIAGNOSTIC": 1, "INDEX": 1, "JOURNAL": 6, "OWNED_FILE_CLASS": 20, "PERSISTENT_MODEL": 13, "PROJECTION": 2, "SECRET": 0},
            "classificationCounts": {"CONTENT_BLOB": 3, "DERIVED_REBUILDABLE": 7, "LOCAL_ONLY": 21, "PRIVATE_DEVICE_ONLY": 3, "REPLICATED": 9},
            "persistentModelNamedGroups": PERSISTENT_MODEL_GROUPS,
            "ownedFileKindNamedGroups": OWNED_FILE_GROUPS,
            "namedGroupsPairwiseDisjoint": True,
            "namedGroupUnionsEqualDeclaredInventories": True,
            "unmatchedDeclaredModelOrFileKind": "FAIL_CLOSED_INCOMPLETE_INVENTORY",
        },
        "currentCatalog": {
            "entryPoint": "CurrentSyncClassificationCatalogV1.current.validate()",
            "registryEntryPoint": "SyncClassificationRegistryV1.validate()",
            "registrationCount": 84,
            "categoryCounts": {"DIAGNOSTIC": 7, "INDEX": 2, "JOURNAL": 21, "OWNED_FILE_CLASS": 20, "PERSISTENT_MODEL": 13, "PROJECTION": 21, "SECRET": 0},
            "classificationCounts": {"CONTENT_BLOB": 4, "DERIVED_REBUILDABLE": 26, "LOCAL_ONLY": 32, "PRIVATE_DEVICE_ONLY": 8, "REPLICATED": 14},
            "searchImplementationPresent": False, "keychainUsageDeclared": False,
            "secretKinds": [], "inventoryIsExplicitAndClosed": True,
            "persistentModelRuntimeNameBinding": {
                "runtimeSource": "PersistentSchemaV4.models",
                "normalization": "STRING_DESCRIBING_TYPE_LAST_COMPONENT_SORTED",
                "requiresUniqueValidTokens": True,
                "equalsDeclaredPersistentModelNames": True,
                "objectIdentifierSetEqualityAlsoRequired": True,
            },
        },
        "classificationGuarantees": {
            "REPLICATED": "ELIGIBLE_FOR_FUTURE_ACCEPTED_MUTATION_TRANSPORT_NOT_TRANSPORT_ITSELF",
            "LOCAL_ONLY": "DESTINATION_LOCAL; PORTABILITY_IS_EXPLICIT_PER_SUBJECT_ROUTE; REVIEWED_DIAGNOSTIC_EXPORT_IS_PORTABLE",
            "DERIVED_REBUILDABLE": "REBUILT_FROM_CANONICAL_INPUTS; PORTABILITY_IS_EXPLICIT_PER_SUBJECT_ROUTE; CURRENT_PORTABLE_PROJECTIONS_ARE_PORTABLE",
            "CONTENT_BLOB": "BOUNDED_IMMUTABLE_HISTORY_ELIGIBLE",
            "PRIVATE_DEVICE_ONLY": "NEVER_PORTABLE_NEVER_TRANSPORTED",
        },
        "sourceSymbols": ["SyncClassificationV1", "SyncSubjectCategoryV1", "SyncClassificationRegistrationV1", "SyncClassificationRegistryV1", "CurrentSyncClassificationCatalogV1"],
        "prohibitedFields": PROHIBITED_FIELDS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def policy_contract() -> dict[str, Any]:
    matrix = [
        {"classification": "REPLICATED", "transport": ["FUTURE_ACCEPTED_MUTATION_ELIGIBLE"], "filesystemBackup": ["NOT_APPLICABLE"], "semanticBackup": ["INCLUDE_CANONICAL", "INCLUDE_IMMUTABLE_HISTORY"], "portableExport": ["PORTABLE_CANONICAL", "PORTABLE_IMMUTABLE_HISTORY"], "delete": ["CANONICAL_DELETE", "APPEND_TOMBSTONE", "LOCAL_AUTHORITY"], "erase": ["CLEAR_WITH_WORKSPACE"]},
        {"classification": "LOCAL_ONLY", "transport": ["EXCLUDED"], "filesystemBackup": ["INCLUDED", "EXCLUDED", "NOT_APPLICABLE"], "semanticBackup": ["EXCLUDE"], "portableExport": ["EXCLUDE", "PORTABLE_CANONICAL"], "delete": ["LOCAL_AUTHORITY", "OPERATION_CLEANUP"], "erase": ["RECREATE_EMPTY", "CLEAR_WITH_WORKSPACE", "LOCAL_AUTHORITY"]},
        {"classification": "DERIVED_REBUILDABLE", "transport": ["EXCLUDED"], "filesystemBackup": ["INCLUDED", "EXCLUDED", "NOT_APPLICABLE"], "semanticBackup": ["INCLUDE_CANONICAL", "REBUILD_AFTER_RESTORE"], "portableExport": ["PORTABLE_CANONICAL", "EXCLUDE"], "delete": ["REBUILD"], "erase": ["REBUILD_AFTER_ERASE"]},
        {"classification": "CONTENT_BLOB", "transport": ["FUTURE_BOUNDED_BLOB_ELIGIBLE"], "filesystemBackup": ["INCLUDED", "NOT_APPLICABLE"], "semanticBackup": ["INCLUDE_IMMUTABLE_HISTORY"], "portableExport": ["PORTABLE_IMMUTABLE_HISTORY"], "delete": ["CANONICAL_DELETE"], "erase": ["CLEAR_WITH_WORKSPACE"]},
        {"classification": "PRIVATE_DEVICE_ONLY", "transport": ["EXCLUDED"], "filesystemBackup": ["EXCLUDED", "NOT_APPLICABLE"], "semanticBackup": ["EXCLUDE"], "portableExport": ["EXCLUDE"], "delete": ["LOCAL_AUTHORITY"], "erase": ["LOCAL_AUTHORITY"]},
    ]
    return seal({
        **base("ReplicationPolicyMatrixV1"), "policyAxes": POLICY_AXES,
        "policyAxisCount": 14, "classificationMatrix": matrix,
        "lifecycleAxisBinding": {
            "filesystemBackup": "CurrentSyncLifecycleRouteV1.filesystemBackup",
            "semanticBackup": "CurrentSyncLifecycleRouteV1.semanticBackup",
            "portableExport": "CurrentSyncLifecycleRouteV1.portableExport",
            "axesAreIndependent": True,
            "classificationRowsAreClosedCurrentAllowedSetsNotUniversalSingleValues": True,
            "portableDerivedProfile": "portableProjection",
            "portableLocalProfile": "reviewedDiagnosticExport",
            "replicatedImmutableHistorySubjects": ["MutationEnvelopeV1", "MutationHistoryQuarantineRecordV1", "MutationReceiptV1", "ReversalBasisV1", "SemanticReversalReceiptV1"],
        },
        "closedDomains": {
            "authority": ["WORKSPACE_WRITER", "IMMUTABLE_CONTENT_WRITER", "LOCAL_DEVICE", "DERIVED_FROM_CANONICAL_INPUTS"],
            "persistence": ["SWIFT_DATA_RECORD", "OWNED_FILE", "NONPERSISTENT"],
            "transport": ["FUTURE_ACCEPTED_MUTATION_ELIGIBLE", "FUTURE_BOUNDED_BLOB_ELIGIBLE", "EXCLUDED"],
            "bootstrap": ["CANONICAL_SNAPSHOT", "IMMUTABLE_HISTORY", "REBUILD_FROM_DEPENDENCIES", "DESTINATION_LOCAL", "EXCLUDED"],
            "privacy": ["WORKSPACE_DATA", "WORKSPACE_CONTENT_BLOB", "PRIVATE_DEVICE_DATA", "SECRET_NEVER_PORTABLE", "NONCUSTOMER_DIAGNOSTIC"],
            "retention": ["UNTIL_CANONICAL_DELETE_OR_ERASE", "IMMUTABLE_HISTORY_UNTIL_ERASE", "REBUILDABLE", "OPERATION_SCOPED", "LOCAL_DEVICE_RETAINED"],
        },
        "validation": {
            "codecReadableVersionsSortedUniquePositive": True, "currentWriteVersionReadable": True,
            "maximumDependencyCount": 64, "dependenciesSortedUnique": True,
            "maximumSizePositiveOrNotApplicable": True, "unknownPolicyOrAxis": "FAIL_CLOSED",
            "privateSecretDiagnosticTransport": "EXCLUDED", "portableSecretsAllowed": False,
            "providerAuthorityOrRetentionExposedAtThisHead": False,
            "providerAuthorityOrRetentionInput": "FAIL_CLOSED_AS_UNKNOWN_ENUM_VALUE",
            "secretNeverPortable": {
                "privacy": "SECRET_NEVER_PORTABLE", "authority": "LOCAL_DEVICE",
                "transport": "EXCLUDED", "bootstrap": ["DESTINATION_LOCAL", "EXCLUDED"],
                "semanticBackup": "EXCLUDE", "portableExport": "EXCLUDE",
                "delete": "LOCAL_AUTHORITY", "erase": "LOCAL_AUTHORITY",
                "violation": "FAIL_CLOSED_INVALID_POLICY",
            },
            "reviewedDiagnosticExportException": {
                "profile": "reviewedDiagnosticExport", "privacy": "NONCUSTOMER_DIAGNOSTIC",
                "portableExport": "PORTABLE_CANONICAL", "mayApplyToSecret": False,
            },
        },
        "consumerRouting": {
            "outbound": "ONLY_ACCEPTED_MUTATION_ENVELOPES_RECEIPTS_AND_EXPLICIT_CHECKPOINTS",
            "inbound": "ONLY_WORKSPACE_WRITER_PLUS_CONFLICT_POLICY_PLUS_DELETE_WINS_PLUS_RECEIPT_PLUS_IMMUTABLE_BLOB_VALIDATION",
            "semanticBackupExport": "POLICY_BACKUP_AND_EXPORT_DISPOSITIONS",
            "filesystemBackup": "PROTECTED_FILE_POLICY_AND_STREAMING_ARCHIVE_CONTRACT",
            "restore": "VALIDATE_POLICY_AND_REBUILD_DERIVED_OUTPUTS",
            "delete": "POLICY_DELETE_DISPOSITION_AND_DELETION_LEDGER",
            "erase": "POLICY_ERASE_DISPOSITION_AND_VERIFIED_ERASE",
            "rebuildReplay": "DECLARED_CANONICAL_DEPENDENCIES_ONLY",
        },
        "networkTransportImplemented": False, "searchImplementationPresent": False,
        "sourceSymbols": ["ReplicationPolicyV1", "ReplicationCodecV1", "ReplicationSizeLimitV1", "CurrentSyncClassificationCatalogV1"],
        "prohibitedFields": PROHIBITED_FIELDS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def conflict_contract() -> dict[str, Any]:
    dispositions = ["IMMUTABLE_UNION", "STABLE_ID_APPEND_UNION", "MANUAL_RESOLUTION_REQUIRED", "DELETE_WINS", "REBUILD_DERIVED", "RETAIN_LOCAL_ONLY"]
    return seal({
        **base("ConflictPolicyRegistryV1"), "conflictRules": CONFLICT_RULES,
        "conflictRuleCount": 6, "dispositions": dispositions,
        "ruleDispositionMatrix": [{"rule": rule, "disposition": disposition} for rule, disposition in zip(CONFLICT_RULES, dispositions)],
        "conflictIdentity": {
            "includes": ["workspaceScopedSubjectIdentity", "policyID", "policyVersion", "policySHA256", "canonicallySortedCompetitorMutationIDsAndInputSHA256"],
            "excludes": ["destinationReceiptID", "arrivalOrder", "journalPosition", "wallClock", "replicaLocalSequence"],
            "competitorFields": ["mutationID", "canonicalInputSHA256"],
            "normalization": "LOWERCASE_MUTATION_UUID_COLON_SHA256_SORTED_LEXICOGRAPHICALLY",
            "permutationInvariant": True, "twoAndThreeWayPermutationsRequired": True,
            "addRemoveOrChangeCompetitorChangesIdentity": True,
            "duplicateMutationID": "FAIL_CLOSED", "maximumCompetitorCount": 64,
        },
        "resolutionBasis": {
            "frozenFields": ["conflictIdentity", "subject", "policy", "competitors", "causalFrontier", "disposition"],
            "causalFrontierFields": ["baseRevision", "baseSemanticSHA256", "observedInputs"],
            "namedMissingInputDisposition": "DEFER_WITH_EXACT_SORTED_MISSING_INPUTS",
            "allNamedInputsRequiredBeforeResolution": True,
            "lateCompetitorDisposition": "CREATE_DETERMINISTIC_SUCCESSOR_IDENTITY",
            "priorBasisImmutable": True, "lastWriterWinsAllowed": False,
        },
        "ruleSemantics": {
            "IMMUTABLE_VERSION": "UNION_ONLY_IDENTICAL_VERSION_COLLISION_FAILS_CLOSED",
            "STABLE_ID_APPEND_UNION": "UNION_BY_STABLE_ID_CONFLICT_DEFERRED_OR_MANUAL",
            "EXACT_REVISION_MANUAL": "NO_AUTOMATIC_WINNER",
            "DELETE_WINS": "CANONICAL_TOMBSTONE_DOMINATES_NONDELETE_COMPETITOR",
            "DERIVED_REBUILD": "DISCARD_AND_REBUILD_FROM_NAMED_CANONICAL_INPUTS",
            "LOCAL_ONLY": "RETAIN_DESTINATION_LOCAL_VALUE_NO_PORTABLE_MERGE",
        },
        "sourceSymbols": ["ConflictRuleV1", "ConflictPolicyV1", "ConflictIdentityV1.derive", "ConflictResolutionBasisV1.readiness", "ConflictResolutionBasisV1.successor"],
        "prohibitedFields": PROHIBITED_FIELDS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def corpus_contract() -> dict[str, Any]:
    return seal({
        **base("ConflictResolutionCorpusManifestV1"),
        "fixturePath": SOURCE_PATHS[-1], "testPath": SOURCE_PATHS[-2],
        "fixtureSchema": "V21P02C03ReplicationConflictPolicyCorpusV1", "fixtureSchemaVersion": 1,
        "fixtureTopLevelFields": ["schema", "schemaVersion", "cardID", "caseIDs", "inventoryExpectations", "rules", "permutations", "hostileCases", "interruptionBoundaries", "lifecycle", "privacy"],
        "evidence": [{"evidenceID": evidence, "testMethod": method} for evidence, method in zip(EVIDENCE_IDS, TEST_METHODS)],
        "requiredCoverage": {
            "G01": ["EXACT_CURRENT_CATALOG", "ALL_LIFECYCLE_ROUTES", "NO_SEARCH", "NO_SECRETS"],
            "A01": ["ALL_SIX_RULES", "TWO_AND_THREE_WAY_PERMUTATIONS", "ORDER_INDEPENDENT_IDENTITY"],
            "H01": ["UNKNOWN_SCHEMA_SUBJECT_POLICY_RULE", "UNKNOWN_DECLARED_MODEL_OR_FILE_KIND_NAME", "SIZE_LIMIT", "PRIVACY", "SECRET_PORTABILITY_REJECTED", "DEPENDENCY_LEAK", "COLLISION", "PROVIDER_AUTHORITY_REJECTED", "PROVIDER_CONTROLLED_RETENTION_REJECTED"],
            "I01": ["NAMED_INPUT_DEFERRAL", "INTERRUPTION_BOUNDARIES", "NO_PARTIAL_RESOLUTION"],
            "R01": ["FROZEN_BASIS", "RELAUNCH_IDEMPOTENCY", "LATE_COMPETITOR_SUCCESSOR", "PRIOR_BASIS_IMMUTABLE"],
        },
        "hostileFailClosed": True, "customerDataPresent": False, "secretsPresent": False,
        "fixtureGeneratedByTooling": False, "exactFiveTestMethods": True,
        "lifecycle": {
            "persistentMode": "DECLARATION_ONLY", "schemaMigrationRequired": False,
            "backupRestoreDeleteExportCompatibilityRequired": True,
            "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
            "lastAcceptedRegistryRemainsActiveUntilReplacementAccepted": True,
            "unclassifiedSubjectAfterRevert": "FAIL_CLOSED",
        },
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def _strict(value: Any, digest: bool = False) -> dict[str, Any]:
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "required": list(value),
                "properties": {key: _strict(child, key == "artifactDigest") for key, child in value.items()}}
    if isinstance(value, list):
        if not value:
            return {"type": "array", "minItems": 0, "maxItems": 0}
        return {"type": "array", "minItems": len(value), "maxItems": len(value),
                "prefixItems": [_strict(item) for item in value], "items": False}
    if isinstance(value, bool) or value is None or isinstance(value, (int, str)):
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"} if digest else {"const": value}
    raise ContractError(f"unsupported schema value: {type(value)}")


def schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value)
    result.update({"$schema": "https://json-schema.org/draft/2020-12/schema",
                   "$id": f"https://assetrounds.invalid/v23/{value['schema']}.schema.json", "title": title})
    return result


def _rows(root: Path, generated: dict[str, bytes]) -> list[dict[str, Any]]:
    rows = []
    for path in MANIFEST_INPUT_PATHS:
        data = generated.get(path)
        if data is None:
            item = root / path
            if not item.is_file():
                raise ContractError(f"missing manifest input: {path}")
            data = item.read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    return rows


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = _rows(root, generated)
    return seal({
        **base("V23-P02-C03-tooling-manifest"),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE),
        "toolingPaths": TOOL_PATHS, "toolingPathCount": len(TOOL_PATHS),
        "sourcePaths": SOURCE_PATHS, "sourcePathCount": len(SOURCE_PATHS),
        "generatedPaths": GENERATED_PATHS,
        "artifacts": rows, "artifactCount": len(rows), "artifactSetDigest": sha(pretty(rows)),
        "persistentSchemaActivatedByTooling": False, "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    registry = registry_contract(); policy = policy_contract()
    conflict = conflict_contract(); corpus = corpus_contract()
    generated = {
        REGISTRY_SCHEMA: pretty(schema("SyncClassificationRegistryV1", registry)),
        POLICY_SCHEMA: pretty(schema("ReplicationPolicyMatrixV1", policy)),
        CONFLICT_SCHEMA: pretty(schema("ConflictPolicyRegistryV1", conflict)),
        CORPUS_SCHEMA: pretty(schema("ConflictResolutionCorpusManifestV1", corpus)),
        REGISTRY_DOC: pretty(registry), POLICY_DOC: pretty(policy),
        CONFLICT_DOC: pretty(conflict), CORPUS_DOC: pretty(corpus),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated

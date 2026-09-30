#!/usr/bin/env python3
"""Deterministic Card 28 system-health and support tooling contracts.

The module is data-first.  Contract values are frozen here, generated
documents are canonical UTF-8 JSON, and every generated document is sealed
with the SHA-256 of its unsealed body.  The manifest binds the hydrated
fence, including files that are not yet present while the product/test
owners finish their slice.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P02-C08"
TITLE = (
    "System health, operational failures, workflow friction, protected scratch, "
    "MetricKit compatibility, and explicit support export"
)

APP_BASE_HEAD = "5f4259dc9d46090203d59273f0c35b1ab1ee6a0d"
APP_BASE_TREE = "198e918442229b3a64dd854bc8f3ae9ee9922092"
COORDINATION_HEAD = "9a1219ffe4cf56855c47c44a85b7fb3f46b1c799"
COORDINATION_TREE = "062078b5cc177851c1e297b4d493ddd93054f1ad"
COORDINATION_CAS_SEQUENCE = 119
COORDINATION_LEDGER_DIGEST = "8933be2a9f9f79faa2fe9736be7eb9762564145258685e34303dbb87d9d98"
HYDRATION_PROJECTION_DIGEST = "6c21bb0bdee6ef786abb8c8eb22e0be8171ba09c93c35fe40c68b6451273fe7d"
CONTEXT_DIGEST = "f4c82433da05626667d4ae8f47f3fa639eb59bdd529be0557e2f1db983e235e0"
FENCE_DIGEST = "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5"
PREREQUISITE_DIGEST = "762869613302e037463d122dcebf50ed34fa68bce4d211524f1198aed7d9acdf"
TRANSITION_DIGEST = "70e17d89ed8cda171a10839958d44fea9130d40dcee7f585fb8fac83230e4e12"
FENCE_CORRECTION_RECEIPT_DIGEST = "de1d8aa1617b8e965c2b39c498d079a6c2a08d791d8149118244fc1530600b77"
PRIOR_CONTEXT_DIGEST = "38974043ffdb6f96f8e19305c553c55d79e15dbdf048113f76475a5283bac4e1"
PRIOR_FENCE_DIGEST = "2734abad6ebb9e8d98f09ce92e3d4eb00267f8040b9870419eeed84efd5ebc96"
AUTHORITY_RECEIPT_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"
OVERRIDE_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

REGISTER_ROW_DIGEST = "246a85c06cbc8174e3e096f26a3f7b87df76f51fb84491402913939ffb08cf1c"
REGISTER_ROW_LENGTH = 316
DOSSIER_DIGEST = "efc49f07fbae9a5d819e2baf4761092413d2fb870ab5e9e98ff489798268e05d"
DOSSIER_LENGTH = 7086
INHERITED_DIGEST = "53d746da0409703496b1f34ba921456717c914288c93e02550d7698d6f77d7f1"
INHERITED_LENGTH = 15097
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p02-c08-contracts-v1"
GENERATOR_SEED = 230208

CONTRACT_SCRIPT = "Scripts/v23/p02_c08_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c08_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c08_contracts.py"
SYSTEM_HEALTH_SCHEMA = "Scripts/v23/system-health.schema.json"
OPERATIONAL_FAILURE_SCHEMA = "Scripts/v23/operational-failure.schema.json"
WORKFLOW_FRICTION_SCHEMA = "Scripts/v23/workflow-friction.schema.json"
SUPPORT_EXPORT_SCHEMA = "Scripts/v23/support-export.schema.json"
SYSTEM_HEALTH_DOC = "docs/design/v23/tooling/V23P02C08SystemHealthContractV1.json"
LIFECYCLE_DOC = "docs/design/v23/tooling/V23P02C08OperationalDiagnosticsLifecycleContractV1.json"
SUPPORT_EXPORT_DOC = "docs/design/v23/tooling/V23P02C08SupportExportContractV1.json"
CORPUS_DOC = "docs/design/v23/tooling/V23P02C08SystemHealthDiagnosticsCorpusManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C08-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/MetricKitDiagnosticsAdapter.swift",
    "FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift",
    "FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/DeviceLifecycleCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/S2PersistenceLedgerTests.swift",
]
NEW_SOURCE_PATHS = [
    "FieldEvidenceApp/Infrastructure/Diagnostics/SystemHealthContractsV1.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Diagnostics/V21P02C08SystemHealthOperationalDiagnosticsCorpusV1.json",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    SYSTEM_HEALTH_SCHEMA,
    OPERATIONAL_FAILURE_SCHEMA,
    WORKFLOW_FRICTION_SCHEMA,
    SUPPORT_EXPORT_SCHEMA,
    SYSTEM_HEALTH_DOC,
    LIFECYCLE_DOC,
    SUPPORT_EXPORT_DOC,
    CORPUS_DOC,
    MANIFEST,
]
SOURCE_PATHS = (
    EXISTING_PATHS[:9]
    + [NEW_SOURCE_PATHS[0]]
    + EXISTING_PATHS[9:]
    + NEW_SOURCE_PATHS[1:]
)
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = TOOL_PATHS[3:]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
NEW_PATHS = NEW_SOURCE_PATHS + TOOL_PATHS

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_12G01BoundedSystemHealthAndSingleMetricSource",
    "testV9_12A01OperationalFailureRegistryAndDefaultOffFrictionAreClosed",
    "testV9_12H01SupportExportRejectsCustomerDataAndSourceScratch",
    "testV9_12I01StoreScratchAndSupportExportRecoverWithoutDuplicateEffects",
    "testV9_12R01MigrationResetEraseAndBootstrapRemainDeviceLocal",
]

HEALTH_STATES = ["DEGRADED", "HEALTHY", "UNAVAILABLE", "UNKNOWN"]
FAILURE_DOMAINS = [
    "BACKUP", "CAPABILITY", "CANCELLATION", "CONCURRENCY", "CONTENT",
    "COMMERCE", "DIAGNOSTICS", "EXPORT", "PERMISSION", "PERSISTENCE",
    "PROTECTED_DATA", "REPORT", "STORAGE",
]
FAILURE_CODES = [
    "BACKUP_EXPORT_FAILED", "BACKUP_RESTORE_FAILED", "BACKUP_SOURCE_CHANGED",
    "CAPABILITY_UNAVAILABLE", "CONCURRENT_OPERATION", "CONTENT_READ_FAILED",
    "COMMERCE_UNAVAILABLE", "CORRUPT_OPERATIONAL_STORE",
    "DIAGNOSTICS_WRITE_FAILED", "EXPORT_CANCELLED", "EXPORT_FAILED",
    "INTERRUPTED", "PARTIAL_SAFE_STATE", "PERMISSION_DENIED",
    "PERSISTENCE_MIGRATION_REQUIRED", "PROTECTED_DATA_UNAVAILABLE",
    "REPORT_RENDER_FAILED", "REPORT_UNAVAILABLE", "REQUIRED_FILE_MISSING",
    "RESTART_REQUIRED", "RESUME_REQUIRED", "STORAGE_CAPACITY_INSUFFICIENT",
    "STORAGE_WRITE_FAILED", "UNKNOWN", "USER_CANCELLED",
]
TYPED_ERROR_MAPPING = {
    "provisionalKernelOnly": True,
    "shippingBoundaryAdoption": "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION",
    "underlyingFailureCanBecomeEmptySuccess": False,
    "storeWriteFailurePropagates": True,
    "cases": [
        {
            "id": "persistence-invalid-digest",
            "boundary": "PERSISTENCE",
            "typedError": "StoreMigrationFailure.invalidDigest",
            "expectedCode": "PERSISTENCE_MIGRATION_REQUIRED",
            "expectedPrimaryAction": "RESTART",
            "expectedRetryability": "NOT_RETRYABLE",
            "expectedPrivacyClass": "AGGREGATE",
        },
        {
            "id": "content-malformed-source",
            "boundary": "CONTENT",
            "typedError": "MediaImportErrorV1.malformedSource",
            "expectedCode": "CONTENT_READ_FAILED",
            "expectedPrimaryAction": "RETRY",
            "expectedRetryability": "RETRY_IMMEDIATELY",
            "expectedPrivacyClass": "AGGREGATE",
        },
        {
            "id": "report-write-failed",
            "boundary": "REPORT",
            "typedError": "ReportRenderServiceError.writeFailed",
            "expectedCode": "REPORT_RENDER_FAILED",
            "expectedPrimaryAction": "RETRY",
            "expectedRetryability": "RETRY_IMMEDIATELY",
            "expectedPrivacyClass": "AGGREGATE",
        },
        {
            "id": "backup-source-changed",
            "boundary": "BACKUP",
            "typedError": "BackupExportServiceError.sourceChanged",
            "expectedCode": "BACKUP_SOURCE_CHANGED",
            "expectedPrimaryAction": "RETRY",
            "expectedRetryability": "RETRY_AFTER_CONDITION_CHANGES",
            "expectedPrivacyClass": "AGGREGATE",
        },
        {
            "id": "permission-invalid-file-authority",
            "boundary": "PERMISSION_FILE_AUTHORITY",
            "typedError": "ApplicationFileAuthorityErrorV1.invalidComponent",
            "expectedCode": "PERMISSION_DENIED",
            "expectedPrimaryAction": "OPEN_SETTINGS",
            "expectedRetryability": "RETRY_AFTER_CONDITION_CHANGES",
            "expectedPrivacyClass": "AGGREGATE",
        },
        {
            "id": "commerce-product-unavailable",
            "boundary": "COMMERCE",
            "typedError": "StoreKitProductLoaderError.unavailable",
            "expectedCode": "COMMERCE_UNAVAILABLE",
            "expectedPrimaryAction": "RETRY",
            "expectedRetryability": "RETRY_AFTER_CONDITION_CHANGES",
            "expectedPrivacyClass": "AGGREGATE",
        },
        {
            "id": "unrecognized-fails-closed",
            "boundary": "PERSISTENCE",
            "typedError": "OperationalDiagnosticsValidationFailureV1.invalidValue",
            "expectedCode": "UNKNOWN",
            "expectedPrimaryAction": "CONTACT_SUPPORT",
            "expectedRetryability": "NOT_RETRYABLE",
            "expectedPrivacyClass": "AGGREGATE",
        },
    ],
}
TYPED_ERROR_MAPPING_POLICY = {
    "boundaryType": "OperationalFailureBoundaryV1",
    "mapperType": "OperationalFailureMapperV1",
    "failureOnlyAPI": "recordAndRethrowOperationalFailure",
    "boundaryCases": [
        "PERSISTENCE", "CONTENT", "REPORT", "BACKUP",
        "PERMISSION_FILE_AUTHORITY", "COMMERCE",
    ],
    "unknownFallbackCode": "UNKNOWN",
    "mapsByTypedBoundaryOnly": True,
    "usesReflection": False,
    "usesLocalizedStrings": False,
    "usesNSErrorCodes": False,
    "underlyingDescriptionConsulted": False,
    "provisionalKernelOnly": True,
    "shippingBoundaryAdoption": "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION",
}
FAILURE_SEVERITIES = ["INFO", "WARNING", "ERROR", "CRITICAL"]
RETRYABILITY = ["NOT_RETRYABLE", "RETRY_AFTER_CONDITION_CHANGES", "RETRY_IMMEDIATELY"]
SCRATCH_PURPOSES = ["SUPPORT_EXPORT", "CAPTURE", "IMPORT", "SOURCE"]
SUPPORT_ALLOWLIST = [
    "appBuild", "appVersion", "archiveBuildUUIDs", "generatedAt",
    "healthClasses", "operationalCodeCounts", "schemaVersions",
]
FRICTION_STATES = [
    "APP_LAUNCH", "CHECK_DRAFT", "FINALIZATION", "REPORT_DELIVERY",
    "RESTORE", "SUPPORT_EXPORT",
]
SIGNPOST_INTERVALS = [
    "APP_BOOTSTRAP", "BACKUP", "CONTENT_DERIVATIVE", "CONTENT_INGEST",
    "DIAGNOSTICS_STORE_WRITE", "FINALIZATION", "IMPORT_COMMIT",
    "IMPORT_PARSE", "MUTATION_COMMIT", "REPORT_RENDER", "RESTORE",
    "SEARCH_REBUILD", "SCRATCH_LEASE", "STORE_OPEN", "SUPPORT_EXPORT",
]
PROHIBITED_TOKENS = [
    "customerText", "customerMedia", "customerNote", "address",
    "preciseLocation", "entityID", "workspaceID", "localPath", "secret",
    "credential", "rawLog", "rawMetricPayload", "automaticUpload",
    "CloudKit", "CKRecord", "MetricManager", "sessionReplay", "analytics",
]
S2_DIAGNOSTICS_TEST_METHODS = [
    "testDiagnosticsCreatesExactZeroBytesAndReloadsEveryCounterAndBucket",
    "testDiagnosticsCountersAndPurchaseBucketsSaturateAtInt64Max",
    "testMalformedDiagnosticsResetOnlyDiagnosticsAndPreserveDomainSentinels",
    "testDiagnosticsWriteFailureIsNonGatingAndDoesNotInventAnIncrement",
]
S6_ERASE_TEST_METHODS = [
    "testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState",
    "testEveryInterruptionRecoversOldOrFullyErasedNew",
    "testMalformedAuxiliaryTreeFailsBeforeAnyDeletion",
    "testReplacedGenerationAncestorFailsClosedWithoutDeletingEitherTree",
]
V10_03_TEST_METHODS = [
    "testV10_03G01CatalogCompletenessAndLifecycleRouting",
    "testV10_03A01SixRuleMatrixAndPermutationIdentity",
    "testV10_03H01UnknownLimitsPrivacyDependencyLeakAndCollisionRejection",
    "testV10_03I01NamedInputsDeferredAndInterruptionBoundaries",
    "testV10_03R01FrozenBasisRelaunchIdempotencyAndLateCompetitor",
]

SUPPORT_STORE_BOUNDS = {
    "maximumRecordBytes": 16_384,
    "maximumTotalBytes": 524_288,
    "maximumRecords": 128,
}
SCRATCH_BOUNDS = [
    {"purpose": "SUPPORT_EXPORT", "maximumBytes": 1_048_576, "maximumLifetimeSeconds": 900},
    {"purpose": "CAPTURE", "maximumBytes": 536_870_912, "maximumLifetimeSeconds": 7_200},
    {"purpose": "IMPORT", "maximumBytes": 4_294_967_296, "maximumLifetimeSeconds": 14_400},
    {"purpose": "SOURCE", "maximumBytes": 4_294_967_296, "maximumLifetimeSeconds": 14_400},
]


class ContractError(ValueError):
    """Raised when the frozen Card 28 inputs cannot be projected."""


def pretty(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        + "\n"
    ).encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "physicalEvidenceComplete": False,
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseReady": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": 28,
        "title": TITLE,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "lineageSource": "V21-P02-C08",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion",
        "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "authorityReceiptDigest": AUTHORITY_RECEIPT_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST,
        "registerRowLength": REGISTER_ROW_LENGTH,
        "dossierDigest": DOSSIER_DIGEST,
        "dossierLength": DOSSIER_LENGTH,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "inheritedV21BlockLength": INHERITED_LENGTH,
        "foundationRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DIGEST,
        "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P02-C07"],
        "invalidationConsumers": ["V23-P02-C09", "V23-P02-C10"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema_name: str) -> dict[str, Any]:
    return {
        "schema": schema_name,
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
    }


def source_bindings() -> list[dict[str, Any]]:
    def binding(path: str, owner: str, symbols: list[str], tokens: list[str]) -> dict[str, Any]:
        return {
            "path": path,
            "owner": owner,
            "symbols": symbols,
            "requiredTokens": tokens,
        }

    return [
        binding(
            EXISTING_PATHS[0],
            "V23-P02-C08",
            [
                "DiagnosticsStore", "DiagnosticsV1", "DeviceOperationalSupportStoreV2",
                "DeviceOperationalSupportEnvelopeV2", "PinnedDiagnosticsAuthority",
            ],
            [
                "DiagnosticsStore", "DiagnosticsV1", "operationalSupportSnapshot",
                "DeviceOperationalSupportStoreV2", "DeviceOperationalSupportEnvelopeV2",
                "PinnedDiagnosticsAuthority", "canonicalData", "canonicalRecordData",
                "persist", "resetOperationalSupport", "isExactlyZero",
                "OperationalFailureBoundaryV1", "OperationalFailureMapperV1",
                "recordAndRethrowOperationalFailure", "at boundary:",
            ],
        ),
        binding(
            EXISTING_PATHS[1],
            "V23-P02-C08",
            [
                "DiagnosticExportV1", "MetricKitSummaryV1", "SupportBundleBuilderV1",
                "SupportBundleBuilderFailureV1", "SupportExportResultV1",
            ],
            [
                "DiagnosticExportV1", "MetricKitSummaryV1", "canonical", "generatedAt",
                "SupportBundleBuilderV1", "SupportBundleBuilderFailureV1", "alreadyFinished",
                "finish(", "prepared",
            ],
        ),
        binding(
            EXISTING_PATHS[2],
            "V23-P02-C08",
            ["DiagnosticsLogger", "DiagnosticsLogEvent"],
            ["DiagnosticsLogger", "DiagnosticsLogEvent", "SUPPORT_EXPORT_FAILED", "privacy"],
        ),
        binding(
            EXISTING_PATHS[3],
            "V23-P02-C08",
            ["MetricKitDiagnosticsAdapter", "MetricKitReportingSourceV1", "MXMetricManagerSubscriber"],
            [
                "MetricKitDiagnosticsAdapter", "MetricKitReportingSourceV1", "MXMetricManager",
                "MetricReportingSource", "MetricReportingSourceContractV1", "sourceCount",
                "permitsSecondReportingSource", "registrationLock", "NSLock",
                "desiredRegistration", "appliedRegistration", "isDrivingRegistration",
                "requestRegistration",
                "start()", "stop()", "shared",
            ],
        ),
        binding(
            EXISTING_PATHS[4],
            "V23-P02-C08",
            ["StoragePreflightService"],
            [
                "StoragePreflightService", "StoragePreflightError",
                "insufficientCapacity", "capacityUnavailable", "requiredBytes", "availableBytes",
            ],
        ),
        binding(
            EXISTING_PATHS[5],
            "V23-P02-C08",
            ["OwnedStorageLedgerV1", "OwnedStorageLedgerFailureV1", "OwnedStorageSnapshotV1"],
            ["OwnedStorageLedgerV1", "snapshot", "reserve", "release", "reconcile",
             "reservationLimitExceeded", "maximumActiveReservationCount",
             "attemptCollision", "adoptExistingFileIfIdentical", "recoverScratchLeases",
             "eraseScratchData", "invalidLease"],
        ),
        binding(
            EXISTING_PATHS[6],
            "V23-P02-C08",
            ["DeviceLifecycleCoordinatorV1", "DeviceLifecycleReducerV1"],
            [
                "DeviceLifecycleCoordinatorV1", "DeviceLifecycleReducerV1",
                "ProtectedDataLifecycleStateV1", "SceneLifecycleStateV1", "DeviceLifecycleEventV1",
                "DeviceLifecycleActionV1", "DeviceLifecycleTransitionV1", "initiallyConservative",
                "suspendForLifecycle", "resumeAfterLifecycle", "resetDeviceLocalState",
                "recoverScratchLeases", "pendingActions",
            ],
        ),
        binding(
            EXISTING_PATHS[7],
            "V23-P02-C08",
            ["EraseAllService"],
            [
                "EraseAllService", "EraseAllFailurePoint", "EraseGenerationDrainProof",
                "erase(", "completeCleanup", "eraseScratchData", "resetOperationalSupport",
                "canonicalDiagnosticsZero", "acceptDescriptorErasedZero", "isExactlyZero",
            ],
        ),
        binding(
            EXISTING_PATHS[8],
            "V23-P02-C08",
            ["CurrentSyncClassificationCatalogV1"],
            [
                "CurrentSyncClassificationCatalogV1", "CurrentSyncLifecycleRouteV1",
                "CurrentReplayDispositionV1", "diagnostic", "diagnosticNames", "diagnosticSubjects",
                "lifecycleRoutes", "lifecycleRoute", "makeAdditionalRegistrations", "validate",
                "portableExport", "semanticBackup", "erase", "replay", "searchImplementationPresent",
            ],
        ),
        binding(
            EXISTING_PATHS[9],
            "V23-P02-C08",
            ["S6_6EraseRecoveryTests"],
            [
                "S6_6EraseRecoveryTests", *S6_ERASE_TEST_METHODS, "EraseAllFailurePoint",
                "EraseAllService", "erase(", "cleanupDeferred", "generationID",
                "currentGenerationID", "retiredGenerationIDs", "canonicalOperationalSupportData",
                "DeviceOperationalSupportSnapshotV2", "injectedFailure", "invalidAuthority",
            ],
        ),
        binding(
            EXISTING_PATHS[10],
            "V23-P02-C08",
            ["V10_03ReplicationConflictRegistryTests", "CurrentSyncClassificationCatalogV1"],
            [
                "V10_03ReplicationConflictRegistryTests", *V10_03_TEST_METHODS,
                "CurrentSyncClassificationCatalogV1", "registrations", "persistentModelSubjects",
                "ownedFileClassSubjects", "portableContentProjectionSubjects",
                "derivedIndexProjectionSubjects", "journalRecoverySubjects", "diagnosticSubjects",
                "lifecycleRoute", "validate", "searchImplementationPresent", "keychainUsageDeclared",
                "ConflictRuleV1", "ReplicationPolicyV1", "privateDeviceOnly", "noncustomerDiagnostic",
            ],
        ),
        binding(
            EXISTING_PATHS[11],
            "V23-P02-C08",
            ["S2PersistenceLedgerTests", "DeviceOperationalSupportSnapshotV2"],
            S2_DIAGNOSTICS_TEST_METHODS + [
                "DeviceOperationalSupportSnapshotV2", "operationalSupportSnapshot",
                "canonicalOperationalSupportData", "canonicalDiagnosticsData", "exactZeroDiagnosticsData",
            ],
        ),
        binding(
            NEW_SOURCE_PATHS[0],
            "V23-P02-C08",
            [
                "SystemHealthDiagnosticsV1", "OperationalFailureV1",
                "OperationalFailureRegistryV1", "DeviceOperationalSupportStoreSchemaV2",
                "OperationalFailureBoundaryV1", "OperationalFailureMapperV1",
                "ScratchDataLeaseV1", "SupportBundleManifestV1", "SupportExportResultV1",
                "WorkflowFrictionProfileV1", "LocalDiagnosticsPreferenceV1",
            ],
            [
                "SystemHealthDiagnosticsV1", "OperationalFailureV1",
                "OperationalFailureRegistryV1", "DeviceOperationalSupportStoreSchemaV2",
                "OperationalFailureBoundaryV1", "OperationalFailureMapperV1",
                "maximumRecordBytes", "maximumTotalBytes", "maximumRecords",
                "ScratchDataLeaseV1", "SUPPORT_EXPORT", "CAPTURE", "IMPORT", "SOURCE",
                "bootstrapOnly", "containsCustomerContent",
                "permitsAutomaticUpload", "COMPLETE", "SupportExportTerminalTokenV1",
                "terminalToken", "beginTerminalDisposition", "rollbackTerminalDisposition",
                "commitTerminalDisposition", "available", "inProgress", "retryable", "finished",
                "switch boundary", "return .unknown",
            ],
        ),
        binding(
            NEW_SOURCE_PATHS[1],
            "V23-P02-C08",
            ["Card28EvidenceTests"],
            TEST_METHODS + [
                "XCTAssertEqual", "XCTAssertFalse", "XCTAssertThrowsError",
                "canonicalOpenCount", "networkRequestCount", "SupportBundleBuilderV1",
                "bootstrapOnly", "eraseScratchData", "DeviceOperationalSupportStoreSchemaV2",
                "operationalSupportSnapshot", "resetOperationalSupport", ".complete",
                "OperationalFailureBoundaryV1", "OperationalFailureMapperV1",
                "recordAndRethrowOperationalFailure", "typedErrorMapping",
                "provisionalKernelOnly", "shippingBoundaryAdoption",
            ],
        ),
        binding(
            NEW_SOURCE_PATHS[2],
            "V23-P02-C08",
            ["V21P02C08SystemHealthOperationalDiagnosticsCorpusV1"],
            [
                "schemaVersion", "fixtureIdentity", "clock", "bounds", "metricCompatibility",
                "health", "failureCodes", "unknownFailure", "typedErrorMapping",
                "supportExport", "storeCases", "scratchIsolation", "workflowFriction",
                "logging", "resetErase",
            ],
        ),
    ]


def privacy_boundary() -> dict[str, Any]:
    return {
        "allowlistOnly": True,
        "forbiddenFields": [
            "customerText", "customerMedia", "customerNote", "addresses",
            "preciseLocation", "stableEntityIdentifiers", "workspaceIdentifiers",
            "localPaths", "secrets", "credentials", "rawLogs", "rawMetricPayloads",
        ],
        "forbiddenBehaviors": [
            "automaticUpload", "remoteTelemetry", "analytics", "sessionReplay",
            "includeEverything", "readBackOSLog",
        ],
        "noNetwork": True,
        "noCustomerContent": True,
        "noSecrets": True,
        "noRawLogs": True,
    }


def common_contract_fields() -> dict[str, Any]:
    return {
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "persistentSchema": "DeviceOperationalSupportStoreSchemaV2",
        "schemaBehaviorDelta": True,
        "migrationBehaviorDelta": True,
        "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True,
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    }


def system_health_contract() -> dict[str, Any]:
    failure_registry = {
        "type": "OperationalFailureRegistryV1",
        "version": 1,
        "codes": FAILURE_CODES,
        "domains": FAILURE_DOMAINS,
        "severities": FAILURE_SEVERITIES,
        "retryability": RETRYABILITY,
        "exactlyOneDescriptorPerCode": True,
        "typedUnderlyingErrorsCannotBecomeEmptySuccess": True,
    }
    return seal({
        **base("V23P02C08SystemHealthContractV1"),
        **common_contract_fields(),
        "owner": "SystemHealthDiagnosticsV1",
        "health": {
            "schemaVersion": 1,
            "states": HEALTH_STATES,
            "maximumFailureCount": 64,
            "fields": ["schemaVersion", "generatedAt", "state", "failures", "metricKit"],
            "boundedLocalSummary": True,
            "customerOrWorkPayload": False,
        },
        "operationalFailure": {
            "schemaVersion": 1,
            "maximumFactCount": 16,
            "requiredDescriptorFields": [
                "registryVersion", "code", "domain", "severity", "retryability",
                "operation", "owner", "primaryAction", "fallbackAction",
                "helpTopic", "privacyClass",
            ],
            "occurrenceCountPositive": True,
            "factsUniqueAndBounded": True,
            "registry": failure_registry,
            "typedErrorMapping": TYPED_ERROR_MAPPING,
            "typedErrorMappingPolicy": TYPED_ERROR_MAPPING_POLICY,
            "stableUserRecovery": True,
        },
        "typedErrorMapping": TYPED_ERROR_MAPPING,
        "typedErrorMappingPolicy": TYPED_ERROR_MAPPING_POLICY,
        "metricSource": {
            "sourceType": "MetricReportingSourceV1",
            "sourceContractType": "MetricReportingSourceContractV1",
            "activeSourceCount": 1,
            "sourceCount": 1,
            "ios18Source": "MXMetricManager",
            "retainedSource": "IOS18_METRICKIT_FALLBACK",
            "ios18FallbackRetained": True,
            "futureNonBetaSubstitutionAllowed": True,
            "permitsBetaOnlyAPI": False,
            "betaMetricManagerAdopted": False,
            "permitsSecondReportingSource": False,
            "betaOnlyAdoptionRejected": True,
            "registration": {
                "serialized": True,
                "desiredStateConverges": True,
                "externalCallsOutsideLock": True,
                "reentrantCallbacksSafe": True,
                "duplicateStartIsIdempotent": True,
                "duplicateStopIsIdempotent": True,
                "soleSource": "MetricKitReportingSourceV1",
            },
            "retainedSummaryFields": [
                "crashCount", "hangCount", "launchTimeMilliseconds", "peakMemoryBytes",
            ],
            "rawPayloadPersisted": False,
        },
        "logging": {
            "adapter": "DiagnosticsLogger",
            "registry": "OperationalLogRegistryV1",
            "signpostRegistry": "PerformanceSignpostRegistryV1",
            "signpostIntervals": SIGNPOST_INTERVALS,
            "signpostCount": len(SIGNPOST_INTERVALS),
            "staticCodesOnly": True,
            "boundedClassesOnly": True,
            "balancedSignpostIntervals": True,
            "rawOSLogExport": False,
            "customerIdentityInLog": False,
        },
        "workflowFriction": {
            "declarationOnly": True,
            "defaultEnabled": False,
            "productionWriteCount": 0,
            "networkRequestCount": 0,
            "customerContentAllowed": False,
            "persistedPreference": False,
            "laterOwner": "P02-C10_SETTINGS_REGISTRY",
        },
        "injectedClock": {
            "required": True,
            "wallClockSource": "injected",
            "monotonicSource": "injected",
            "systemClockNotHardWiredInTests": True,
        },
        "privacy": privacy_boundary(),
        "sourceBindings": source_bindings(),
    })


def lifecycle_contract() -> dict[str, Any]:
    return seal({
        **base("V23P02C08OperationalDiagnosticsLifecycleContractV1"),
        **common_contract_fields(),
        "owner": "DeviceOperationalSupportStoreV2",
        "store": {
            "type": "DeviceOperationalSupportStoreV2",
            "schema": "DeviceOperationalSupportStoreSchemaV2",
            "schemaVersion": 2,
            "cloudKitDatabase": "NONE",
            "fileProtection": "COMPLETE",
            "backupExcluded": True,
            "canonicalWorkspaceOpenAllowed": False,
            "canonicalWorkspaceWriteAllowed": False,
            "bounds": SUPPORT_STORE_BOUNDS,
            "protectionPolicy": "COMPLETE",
            "accounting": {
                "maximumActiveReservationCount": 10_000,
                "exactCapAdmissionIsIdempotent": True,
                "invalidMetadataDoesNotMutate": True,
                "recoveryErrorsNormalizeToTypedFailure": True,
            },
            "migration": {
                "absent": "CREATE_V2",
                "v1": "MIGRATE_V1_TO_V2",
                "olderOrSkipped": "FORWARD_FIX_REQUIRED",
                "unknown": "QUARANTINE_AND_FAIL_CLOSED",
                "corrupt": "QUARANTINE_AND_RECREATE",
                "failed": "VISIBLE_TYPED_FAILURE_NO_EMPTY_SUCCESS",
                "sameInputRetry": "IDEMPOTENT",
            },
            "quarantine": {
                "unknownOrCorrupt": True,
                "preservesPriorAcceptedStore": True,
                "reconstructsEmptyV2": True,
            },
            "reset": "REMOVE_OPERATIONAL_HISTORY_ONLY",
            "erase": "REMOVE_OPERATIONAL_HISTORY_AND_SCRATCH",
            "deletionForSpace": False,
        },
        "scratch": {
            "leaseType": "ScratchDataLeaseV1",
            "soleSharedRoot": True,
            "purposes": SCRATCH_PURPOSES,
            "bounds": SCRATCH_BOUNDS,
            "protection": "COMPLETE",
            "backupExcluded": True,
            "ownerOperationBound": True,
            "purposeIsolation": True,
            "crashRecovery": "RECOVER_EXPIRED_AND_DELETE",
            "terminalDeletion": ["CANCELLED", "COMPLETED", "FAILED", "EXPIRED"],
            "injectedClock": True,
            "supportExportPurposeOnly": True,
            "sourceScratchNeverFeedsSupport": True,
            "recovery": {
                "relaunchRecovery": True,
                "expiredLeasesDeleted": True,
                "leaseCollisionFailsClosed": True,
                "idempotentAcquireSameRequest": True,
                "idempotentTerminalRelease": True,
                "deletionTombstonePrefix": ".deleting-",
                "tombstoneIdentityVerified": True,
                "tombstoneCollisionPreservesOriginal": True,
                "unknownOrCorruptLeaseFailsClosed": True,
                "noAutomaticDeleteForSpace": True,
            },
        },
        "supportStoreLifecycle": {
            "startupBootstrap": True,
            "bootstrapDoesNotOpenCanonicalStore": True,
            "protectedDataDenied": "BLOCK_VISIBLE_FAILURE",
            "lowStorage": "REFUSE_BEFORE_WRITE",
            "permissionDenied": "VISIBLE_FAILURE_WITH_MANUAL_FALLBACK",
            "concurrency": "ONE_IDEMPOTENT_RETRY_OR_FAIL",
            "interruption": "RELAUNCH_RECOVERS_OR_FAILS_CLOSED",
            "unknownError": "UNKNOWN_STABLE_FAILURE",
        },
        "exportLifecycle": {
            "userInitiated": True,
            "previewBeforeShare": True,
            "allowlist": SUPPORT_ALLOWLIST,
            "maximumCanonicalBytes": 524_288,
            "automaticUpload": False,
            "shareRecallable": False,
            "states": ["PREVIEW", "CANCELLED", "SHARE_COMPLETED", "EXPIRED", "FAILED"],
            "cleanupOnEveryTerminalState": True,
            "bootstrapOnlyMode": True,
        },
        "eraseReset": {
            "resetRemovesOperationalRows": True,
            "eraseRemovesOperationalRows": True,
            "eraseRemovesScratch": True,
            "canonicalWorkspaceMutationCount": 0,
            "immutableReportsPreserved": True,
        },
        "lifecycleExclusions": {
            "canonicalBackup": False,
            "workspaceSync": False,
            "reportSearch": False,
            "customerPayload": False,
            "phase10PollingDuringParallelExecution": False,
        },
        "privacy": privacy_boundary(),
        "sourceBindings": source_bindings(),
    })


def support_export_contract() -> dict[str, Any]:
    return seal({
        **base("V23P02C08SupportExportContractV1"),
        **common_contract_fields(),
        "owner": "SupportBundleBuilderV1",
        "bundle": {
            "manifestType": "SupportBundleManifestV1",
            "schemaVersion": 1,
            "maximumCanonicalBytes": 524_288,
            "maximumMemberCount": 2,
            "allowlist": SUPPORT_ALLOWLIST,
            "allowlistedDataIsDeviceOperationalOnly": True,
            "containsCustomerContent": False,
            "containsCustomerIdentifier": False,
            "containsRawLogs": False,
            "permitsAutomaticUpload": False,
            "bootstrapOnlyMembers": ["appBuild", "appVersion", "generatedAt", "operationalCodeCounts"],
        },
        "result": {
            "type": "SupportExportResultV1",
            "userInitiated": True,
            "previewRequired": True,
            "cancelIsTerminal": True,
            "shareIsExplicitExternalEffect": True,
            "shareCannotClaimRecall": True,
            "expiryIsTerminal": True,
            "failureIsTypedAndVisible": True,
            "networkRequestCount": 0,
            "automaticUpload": False,
            "noMailOrShareFallback": "COPY_SUPPORT_ADDRESS_OR_SAVE_TO_FILES",
        },
        "terminalReplay": {
            "stateMachine": ["AVAILABLE", "IN_PROGRESS", "RETRYABLE", "FINISHED"],
            "beginRequiresPrepared": True,
            "sameDispositionRetryAfterCleanupFailure": True,
            "changedDispositionRejected": True,
            "concurrentClaimRejected": True,
            "finishedClaimRejected": True,
            "receiptPublishedOnlyAfterCleanup": True,
            "cleanupFailureIsRetryable": True,
            "leaseReleasedExactlyOnceOnCommit": True,
        },
        "scratch": {
            "purpose": "SUPPORT_EXPORT",
            "maximumBytes": 1_048_576,
            "maximumLifetimeSeconds": 900,
            "leaseType": "ScratchDataLeaseV1",
            "protection": "COMPLETE",
            "sourcePurposesRejected": ["CAPTURE", "IMPORT", "SOURCE"],
            "deleteAfterPreviewCancelShareExpiryFailure": True,
            "recovery": {
                "relaunchRecovery": True,
                "expiredLeasesDeleted": True,
                "leaseCollisionFailsClosed": True,
                "idempotentAcquireSameRequest": True,
                "idempotentTerminalRelease": True,
                "deletionTombstonePrefix": ".deleting-",
                "tombstoneIdentityVerified": True,
                "tombstoneCollisionPreservesOriginal": True,
                "unknownOrCorruptLeaseFailsClosed": True,
                "noAutomaticDeleteForSpace": True,
            },
        },
        "bootstrap": {
            "canonicalStoreOpenCount": 0,
            "usableUnderCorruptStore": True,
            "usableUnderProtectedDataDenial": True,
            "usableUnderFailedMigration": True,
            "usableUnderLowStorage": True,
            "successRequiresDurableOperationalReceipt": True,
        },
        "redaction": {
            "rejectsCustomerText": True,
            "rejectsMedia": True,
            "rejectsAddress": True,
            "rejectsPreciseLocation": True,
            "rejectsEntityID": True,
            "rejectsLocalPath": True,
            "rejectsSecret": True,
            "rejectsRawLog": True,
            "rejectsSourceScratch": True,
        },
        "privacy": privacy_boundary(),
        "sourceBindings": source_bindings(),
    })


def corpus_contract() -> dict[str, Any]:
    return seal({
        **base("V23P02C08SystemHealthDiagnosticsCorpusManifestV1"),
        **common_contract_fields(),
        "fixturePath": NEW_SOURCE_PATHS[2],
        "fixtureSchema": "V21P02C08SystemHealthOperationalDiagnosticsCorpusV1",
        "fixtureSchemaVersion": 1,
        "fixtureIdentity": "V21-P02-C08-SYSTEM-HEALTH-OPERATIONAL-DIAGNOSTICS-CORPUS-V1",
        "fixtureTopLevelFields": [
            "schemaVersion", "fixtureIdentity", "clock", "bounds", "metricCompatibility",
            "health", "failureCodes", "unknownFailure", "typedErrorMapping",
            "supportExport", "storeCases", "scratchIsolation", "workflowFriction",
            "logging", "resetErase",
        ],
        "fixtureFailureCodes": FAILURE_CODES,
        "fixtureTypedErrorMapping": TYPED_ERROR_MAPPING,
        "fixtureTypedErrorMappingPolicy": TYPED_ERROR_MAPPING_POLICY,
        "fixtureHealthStates": HEALTH_STATES,
        "fixtureScratchPurposes": SCRATCH_PURPOSES,
        "fixtureSupportAllowlist": SUPPORT_ALLOWLIST,
        "fixtureStoreCases": [
            {"id": "absent", "expected": "CREATED_V2"},
            {"id": "upgrade-v1", "expected": "MIGRATED_V1_TO_V2"},
            {"id": "skipped-version", "expected": "FORWARD_FIX_REQUIRED"},
            {"id": "corrupt", "expected": "QUARANTINED_AND_RECREATED"},
            {"id": "protected-data", "expected": "BLOCKED_PROTECTED_DATA"},
            {"id": "low-storage", "expected": "REFUSED_BEFORE_WRITE"},
            {"id": "kill-after-stage", "expected": "RELAUNCH_RECOVERS_ONCE"},
            {"id": "record-bound", "expected": "LIMIT_EXCEEDED"},
            {"id": "total-bound", "expected": "LIMIT_EXCEEDED"},
            {"id": "count-bound", "expected": "LIMIT_EXCEEDED"},
        ],
        "s2PersistenceRegression": {
            "path": EXISTING_PATHS[11],
            "storeSchema": "DeviceOperationalSupportStoreSchemaV2",
            "requiredMethods": S2_DIAGNOSTICS_TEST_METHODS,
            "proofs": [
                "exact-zero-canonical-bytes",
                "reloads-every-counter-and-bucket",
                "int64-saturation-without-overflow",
                "malformed-input-resets-only-diagnostics",
                "write-failure-is-non-gating",
                "operational-support-snapshot-reloads",
            ],
        },
        "fixtureFrictionStates": FRICTION_STATES,
        "fixtureRequiredScratchCleanup": [
            "CANCELLED", "COMPLETED", "FAILED", "EXPIRED",
        ],
        "fixtureInterruptionBoundaries": [
            "before_atomic_commit", "after_canonical_effect_before_receipt", "after_receipt",
        ],
        "requiredCoverage": {
            "G01": [
                "BOUNDED_SYSTEM_HEALTH_SUMMARY",
                "ONE_MXMETRIC_MANAGER_SOURCE",
                "IOS18_FALLBACK_RETAINED",
                "NO_RAW_PAYLOAD",
            ],
            "A01": [
                "ALL_OPERATIONAL_CODES_HAVE_DESCRIPTOR",
                "TYPED_ERROR_NEVER_EMPTY_SUCCESS",
                "TYPED_ERROR_BOUNDARY_MAPPING_IS_CLOSED",
                "NO_REFLECTION_OR_LOCALIZED_ERROR_MAPPING",
                "WORKFLOW_FRICTION_DEFAULT_OFF_ZERO_WRITES",
                "UNKNOWN_FAILURE_FAILS_CLOSED",
            ],
            "H01": [
                "SUPPORT_ALLOWLIST_REJECTS_CUSTOMER_DATA",
                "CAPTURE_IMPORT_SOURCE_ISOLATED",
                "PROTECTED_LOW_STORAGE_OFFLINE_AND_SHARE_DENIED",
                "HOSTILE_RAW_LOG_AND_SECRET_REJECTION",
                "SCRATCH_TOMBSTONE_IDENTITY_COLLISION_FAIL_CLOSED",
            ],
            "I01": [
                "STORE_ABSENT_UPGRADE_CORRUPT_QUARANTINE",
                "LEASE_TERMINAL_CLEANUP_AND_RELAUNCH",
                "EFFECT_RECEIPT_INTERRUPTION_NO_DUPLICATE_EFFECT",
                "TERMINAL_REPLAY_RETRYABLE_SAME_DISPOSITION",
                "ERASE_RESET_RECONCILES_DEVICE_LOCAL_STATE",
            ],
            "R01": [
                "BOOTSTRAP_WITHOUT_CANONICAL_STORE_OPEN",
                "DEVICE_OPERATIONAL_SCHEMA_V2_BOUNDS",
                "INJECTED_CLOCK_EXPIRY_AND_RECOVERY",
                "NO_BACKUP_SYNC_REPORT_SEARCH_LEAK",
            ],
        },
        "evidence": [
            {"evidenceID": evidence, "family": suffix, "testMethod": method}
            for evidence, suffix, method in zip(
                EVIDENCE_IDS, ("G01", "A01", "H01", "I01", "R01"), TEST_METHODS
            )
        ],
        "hostileCases": [
            "unknown raw error",
            "unknown MetricKit payload class",
            "duplicate subscriber",
            "corrupt operational store",
            "SDK availability mismatch",
            "customer data in support export",
            "source scratch in support export",
            "support output bypasses lease",
            "workflow friction write while OFF",
            "canonical store opened during bootstrap",
        ],
        "exactFiveTestMethods": True,
        "fixtureGeneratedByTooling": False,
        "customerDataPresent": False,
        "secretsPresent": False,
        "nativeOrHostedEvidenceClaimed": False,
        "sourceBindings": source_bindings(),
    })


def _strict(value: Any, key: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {name: _strict(child, name) for name, child in value.items()},
        }
    if isinstance(value, list):
        if not value:
            return {"type": "array", "minItems": 0, "maxItems": 0, "prefixItems": [], "items": False}
        return {
            "type": "array",
            "minItems": len(value),
            "maxItems": len(value),
            "prefixItems": [_strict(item) for item in value],
            "items": False,
        }
    if key == "artifactDigest":
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"const": value}
    if isinstance(value, int):
        return {"const": value}
    if isinstance(value, str):
        return {"const": value}
    raise ContractError(f"unsupported schema value for {key}: {type(value)}")


def schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{value['schema']}.schema.json",
        "title": title,
    })
    return result


def _manifest_rows(root: Path, generated: dict[str, bytes]) -> tuple[list[dict[str, Any]], list[str]]:
    rows: list[dict[str, Any]] = []
    pending: list[str] = []
    for relative in MANIFEST_INPUT_PATHS:
        data = generated.get(relative)
        if data is None:
            path = root / relative
            if not path.is_file():
                pending.append(relative)
                continue
            data = path.read_bytes()
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data)})
    return rows, pending


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows, pending = _manifest_rows(root, generated)
    return seal({
        **base("V23-P02-C08-tooling-manifest"),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": PATH_FENCE,
        "pathFenceCount": len(PATH_FENCE),
        "existingPaths": EXISTING_PATHS,
        "newPaths": NEW_PATHS,
        "sourcePaths": SOURCE_PATHS,
        "sourcePathCount": len(SOURCE_PATHS),
        "toolingPaths": TOOL_PATHS,
        "toolingPathCount": len(TOOL_PATHS),
        "generatedPaths": GENERATED_PATHS,
        "artifacts": rows,
        "artifactCount": len(rows),
        "pendingFencePaths": pending,
        "pendingArtifactCount": len(pending),
        "artifactSetDigest": sha(pretty(rows)),
        "fenceProof": {
            "baseHead": APP_BASE_HEAD,
            "baseTree": APP_BASE_TREE,
            "pathFenceDigest": FENCE_DIGEST,
            "priorPathFenceDigest": PRIOR_FENCE_DIGEST,
            "correctionReceiptDigest": FENCE_CORRECTION_RECEIPT_DIGEST,
            "correctionTransitionDigest": TRANSITION_DIGEST,
            "priorPathCount": 25,
            "pathCount": 27,
            "addedPaths": [
                "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
                "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
            ],
            "allowedDeletePaths": [],
            "allowedRenamePaths": [],
            "priorFenceOverlapCount": 18,
            "authorizedPriorFenceOverlapCount": 18,
            "unauthorizedPriorFenceOverlapCount": 0,
            "activeS10ReservationDigest": RESERVATION_DIGEST,
            "activeS10Overlap": False,
        },
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "persistentSchemaActivatedByTooling": False,
        "schemaBehaviorDelta": True,
        "migrationBehaviorDelta": True,
        "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True,
        "noPersistedMonotonicTicks": True,
        "noCausalWallClockOrdering": True,
        "privacyAllowlistOnly": True,
        "noNetwork": True,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    system = system_health_contract()
    lifecycle = lifecycle_contract()
    export = support_export_contract()
    corpus = corpus_contract()
    generated: dict[str, bytes] = {
        SYSTEM_HEALTH_SCHEMA: pretty(schema("V23P02C08SystemHealthContractV1", system)),
        OPERATIONAL_FAILURE_SCHEMA: pretty(schema("V23P02C08OperationalDiagnosticsLifecycleContractV1", lifecycle)),
        WORKFLOW_FRICTION_SCHEMA: pretty(schema("V23P02C08SupportExportContractV1", export)),
        SUPPORT_EXPORT_SCHEMA: pretty(schema("V23P02C08SystemHealthDiagnosticsCorpusManifestV1", corpus)),
        SYSTEM_HEALTH_DOC: pretty(system),
        LIFECYCLE_DOC: pretty(lifecycle),
        SUPPORT_EXPORT_DOC: pretty(export),
        CORPUS_DOC: pretty(corpus),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated

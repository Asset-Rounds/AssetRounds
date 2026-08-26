#!/usr/bin/env python3
"""Deterministic Card 27 observation and temporal contracts.

This module is intentionally data-first.  The generated documents are
canonical, exact-key projections of the values below; every document is
sealed with the SHA-256 of its unsealed pretty JSON.  The final tooling
manifest seals every other path in the hydrated Card 27 fence.  Source files
are read only to bind their bytes into that manifest; source discovery never
selects contract values.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P02-C07"
TITLE = "ObservationBasisV1, bounded uncertainty, and explicit temporal semantics"

APP_BASE_HEAD = "0a97101d906816fd9a17bdc02d2b42ac02e3616d"
APP_BASE_TREE = "a5432c93afa969d4b936ff313b9cd0985661829e"
COORDINATION_HEAD = "4737a62d29a4e87c8e67341bcc32acb1668bbfe4"
COORDINATION_TREE = "66d2df86c6007fb084a058b8fb0929d5223a47ea"
COORDINATION_CAS_SEQUENCE = 112
COORDINATION_LEDGER_DIGEST = "e264a7a6932757680bd457823c79a056c1e21769278368372f8225c22c2b0968"
HYDRATION_PROJECTION_DIGEST = "18c68d2ffa91ff935c93e30efaf231aca52acee85a3e9d21c59dbf2cb21afe0f"
CONTEXT_DIGEST = "f8ec963ab7e2a2ea1122b34d96e957ade3564748f10a3582619316d825413b8b"
FENCE_DIGEST = "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118"
PREREQUISITE_DIGEST = "a76e7d82ef3e832fb0b4d884f25727fd40cfaa9d4fe0014b2c13cc396627b8a0"
TRANSITION_DIGEST = "a147d23067a61d3797dafc776d5e5bfeb8da2b43f8578ced16b480599e5a57f1"
AUTHORITY_RECEIPT_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"
OVERRIDE_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
REGISTER_ROW_DIGEST = "444712a550a1d0419fe2da21822b2352777c919c7912cad497938d2ec30d7778"
REGISTER_ROW_LENGTH = 269
DOSSIER_DIGEST = "dfbeb39f8f4993fe069aecb29f555e160567df69de1da53e35942b9be1168d5b"
DOSSIER_LENGTH = 6969
INHERITED_DIGEST = "1c469d8e8baa23cf64a446f729eb8f6c52c7e675597182b4cf144cde99f099f6"
INHERITED_LENGTH = 8900
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p02-c07-contracts-v1"
GENERATOR_SEED = 230207

CONTRACT_SCRIPT = "Scripts/v23/p02_c07_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c07_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c07_contracts.py"
BASIS_SCHEMA = "Scripts/v23/observation-basis.schema.json"
TEMPORAL_SCHEMA = "Scripts/v23/temporal-context.schema.json"
LIFECYCLE_SCHEMA = "Scripts/v23/observation-temporal-lifecycle.schema.json"
CORPUS_SCHEMA = "Scripts/v23/observation-temporal-corpus.schema.json"
BASIS_DOC = "docs/design/v23/tooling/V23P02C07ObservationBasisContractV1.json"
TEMPORAL_DOC = "docs/design/v23/tooling/V23P02C07TemporalContextContractV1.json"
LIFECYCLE_DOC = "docs/design/v23/tooling/V23P02C07ObservationTemporalLifecycleContractV1.json"
CORPUS_DOC = "docs/design/v23/tooling/V23P02C07ObservationTemporalCorpusManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C07-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Domain/Models/WorkflowModels.swift",
    "FieldEvidenceApp/Domain/Workflow/TimeContextRule.swift",
    "FieldEvidenceApp/Domain/Workflow/FinalizationContracts.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportCorrectionRule.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V9_08GenerationLeaseTests.swift",
]
NEW_SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Models/ObservationAndTimeModelsV1.swift",
    "FieldEvidenceAppTests/V9_11ObservationTemporalSemanticsTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Observation/V21P02C07ObservationTemporalCorpusV1.json",
]
SOURCE_PATHS = EXISTING_PATHS[:28] + [NEW_SOURCE_PATHS[0]] + EXISTING_PATHS[28:] + NEW_SOURCE_PATHS[1:]
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    BASIS_SCHEMA,
    TEMPORAL_SCHEMA,
    LIFECYCLE_SCHEMA,
    CORPUS_SCHEMA,
    BASIS_DOC,
    TEMPORAL_DOC,
    LIFECYCLE_DOC,
    CORPUS_DOC,
    MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = TOOL_PATHS[3:]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
NEW_PATHS = NEW_SOURCE_PATHS + TOOL_PATHS

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_11G01ObservationBasisRoundTripsIndependentlyFromOutcome",
    "testV9_11A01ReportedInferredAndUnknownRemainDistinct",
    "testV9_11H01DSTGapFoldRollbackUnknownZoneAndNoWallClockCausality",
    "testV9_11I01AtomicInterruptionRetryNeverPersistsPartialPair",
    "testV9_11R01LegacyMigrationPortableReplayDeleteEraseAndQuarantine",
]

OBSERVATION_BASIS_KINDS = [
    "DIRECTLY_OBSERVED", "REPORTED", "INFERRED", "NOT_OBSERVED",
    "UNVERIFIABLE", "UNKNOWN",
]
OBSERVATION_SOURCE_KINDS = ["OBSERVER", "REPORTED_PARTY", "RECORD", "UNKNOWN"]
TIME_DISPOSITIONS = ["UNAMBIGUOUS", "AMBIGUOUS_FOLD", "NONEXISTENT_GAP", "UNKNOWN"]
PROHIBITED_TOKENS = [
    "accountID", "authenticatedUserID", "backgroundDaemon", "CloudKit", "CKRecord",
    "inbox", "outbox", "providerID", "remoteProvider", "serverCursor", "serverRevision",
    "tenantID", "vectorClock", "accessToken", "serviceCredential", "secretMaterial",
]


class ContractError(ValueError):
    """Raised when frozen Card 27 inputs cannot be generated."""


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
        "registerOrdinal": 27,
        "title": TITLE,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "lineageSource": "V21-P02-C07",
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
        "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "foundationRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DIGEST,
        "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P02-C06"],
        "invalidationConsumers": ["V23-P02-C08"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema_name: str) -> dict[str, Any]:
    return {"schema": schema_name, "schemaVersion": 1, "cardID": CARD, "authority": authority()}


def source_bindings() -> list[dict[str, Any]]:
    def binding(path: str, owner: str, symbols: list[str], tokens: list[str]) -> dict[str, Any]:
        return {"path": path, "owner": owner, "symbols": symbols, "requiredTokens": tokens}

    return [
        binding(
            SOURCE_PATHS[0], "V23-P02-C07",
            ["WorkflowRecord"],
            ["WorkflowRecord", "schemaVersion", "recordRevisionRootID", "finalizationMutationID"],
        ),
        binding(
            SOURCE_PATHS[1], "V23-P02-C07",
            ["TimeContextRule", "TemporalContextV1"],
            ["TemporalContextV1", "observedAtUTC", "timeZoneID", "secondsFromGMT", "freezeTemporalContext"],
        ),
        binding(
            SOURCE_PATHS[2], "V23-P02-C07",
            ["FinalizationIntentV1", "FinalizationPayloadV1", "WorkflowRecordPayloadV1", "CanonicalJSONV1"],
            ["WorkflowRecordPayloadV1", "observationBasisV1Data", "temporalContextV1Data", "CanonicalJSONV1", "validObservationAndTime", "canonicalBasis", "canonicalTemporal"],
        ),
        binding(
            SOURCE_PATHS[3], "V23-P02-C07",
            ["ReportCorrectionRule", "ReportCorrectionRuleSource", "ReportCorrectionRuleRequest", "ReportCorrectionRulePlan", "ReportCorrectionRuleError"],
            ["ReportCorrectionRule", "validateEdge", "makePlan", "WorkflowRecordPayloadV1", "frozen", "snapshotSchemaVersion == 2", "observationBasisV1Data", "temporalContextV1Data"],
        ),
        binding(
            SOURCE_PATHS[4], "V23-P02-C07",
            ["ReportSnapshotV1", "ObservationBasisV1", "TemporalContextV1"],
            ["ObservationBasisV1", "TemporalContextV1", "observationBasis", "temporalContext"],
        ),
        binding(
            SOURCE_PATHS[5], "V23-P02-C07",
            ["CheckDraftMutationV1", "ObservationBasisV1", "TemporalContextV1"],
            ["ObservationBasisV1", "TemporalContextV1", "pre-ObservationAndTimeSchemaV1", "observationBasis"],
        ),
        binding(
            SOURCE_PATHS[6], "V23-P02-C07",
            ["PersistentSchemaV4", "PersistentSchemaV5", "ObservationAndTimeRow", "PersistentSchemaMigrationPlanV4"],
            ["PersistentSchemaV4", "PersistentSchemaV5", "ObservationAndTimeRow", "PersistentSchemaV4.models + [ObservationAndTimeRow.self]", "PersistentSchemaMigrationPlanV4", "migrateV4ToV5", "models.count == 14"],
        ),
        binding(
            SOURCE_PATHS[7], "V23-P02-C07",
            ["StoreGenerationFactory"],
            ["StoreGenerationFactory", "migrationID", "generationID", "forward"],
        ),
        binding(
            SOURCE_PATHS[8], "V23-P02-C07",
            ["ObservationAndTimeMigrationV1", "ObservationAndTimeMigrationReceiptV1"],
            ["ObservationAndTimeMigrationV1", "ObservationAndTimeMigrationReceiptV1", "inventedDirectObservation", "legacy"],
        ),
        binding(
            SOURCE_PATHS[9], "V23-P02-C07",
            ["StoreMigrationService"],
            ["schema-migration", "prepared-migration", "migrationID", "StoreMigrationFailure"],
        ),
        binding(
            SOURCE_PATHS[10], "V23-P02-C07",
            ["WorkspaceWriterAdapterV1"],
            ["WorkspaceWriterAdapterV1", "ObservationAndTimeCodecV1", "observationBasisData", "temporalContextData"],
        ),
        binding(
            SOURCE_PATHS[11], "V23-P02-C07",
            ["MutationJournalStoreV1"],
            ["MutationJournalStoreV1", "canonical", "replay", "MutationReceiptRow"],
        ),
        binding(
            SOURCE_PATHS[12], "V23-P02-C07",
            ["V4BackupRecordsV1", "ObservationBasisV1", "TemporalContextV1"],
            ["observationBasisV1Data", "temporalContextV1Data", "recordsSchemaVersion", "Data"],
        ),
        binding(
            SOURCE_PATHS[13], "V23-P02-C07",
            ["BackupCanonicalDecoderV1"],
            ["BackupCanonicalDecoderV1", "decodeRecords", "canonical"],
        ),
        binding(
            SOURCE_PATHS[14], "V23-P02-C07",
            ["BackupCanonicalEncoderV1", "ObservationAndTimeCodecV1"],
            ["BackupCanonicalEncoderV1", "ObservationAndTimeCodecV1", "validObservationAndTime", "includeObservationAndTime"],
        ),
        binding(
            SOURCE_PATHS[15], "V23-P02-C07",
            ["BackupExportService"],
            ["BackupExportService", "exportStreaming", "backupSchemaVersion", "canonical"],
        ),
        binding(
            SOURCE_PATHS[16], "V23-P02-C07",
            ["BackupImportService", "ValidatedV4BackupPackageV1", "BackupImportServiceError"],
            ["BackupImportService", "stageAndValidate", "stageAndValidateOffMain", "validateManifestBounds", "backupSchemaVersion", "persistentSchemaVersion", "recordsSchemaVersion", "(4, 5, 4)", "validateSourceBoundary", "discard"],
        ),
        binding(
            SOURCE_PATHS[17], "V23-P02-C07",
            ["BackupPackageValidatorV1"],
            ["BackupPackageValidatorV1", "validateObservationAndTime", "ObservationAndTimeCodecV1", "could_not_verify"],
        ),
        binding(
            SOURCE_PATHS[18], "V23-P02-C07",
            ["ReplacementRestoreRule", "ReplacementRestoreRuleInput", "ReplacementRestoreRuleError"],
            ["ReplacementRestoreRule", "schemaVersion", "DeletionIdentityV2", "MutationHistoryReceiptRecordV1", "invalidAuthority", "decodeCanonical"],
        ),
        binding(
            SOURCE_PATHS[19], "V23-P02-C07",
            ["BackupRestoreService"],
            ["BackupRestoreService", "restore", "migrationCanonicalRecords", "newGenerationID"],
        ),
        binding(
            SOURCE_PATHS[20], "V23-P02-C07",
            ["ReportSnapshotEncoderV1"],
            ["ReportSnapshotEncoderV1", "ObservationAndTimeCodecV1", "validObservationAndTime", "ObservationBasisV1"],
        ),
        binding(
            SOURCE_PATHS[21], "V23-P02-C07",
            ["ReportDeliveryCoordinator", "ReportDeliveryValue", "ReportDeliveryPreparation", "ReportCorrectionSubmissionResult"],
            ["ReportDeliveryCoordinator", "ReportDeliveryValue", "ReportCorrectionSubmissionResult", "prepareFinalizedReport", "submitCorrection", "validateCompleteSnapshotAuthority", "snapshotSchemaVersion == 2", "WorkflowRecord", "ObservationAndTimeRowStoreV1", "observationBasisV1Data", "temporalContextV1Data"],
        ),
        binding(
            SOURCE_PATHS[22], "V23-P02-C07",
            ["SnapshotValidatorV1"],
            ["SnapshotValidatorV1", "observationBasis", "temporalContext", "validObservationAndTime"],
        ),
        binding(
            SOURCE_PATHS[23], "V23-P02-C07",
            ["ReportRecoveryService"],
            ["ReportRecoveryService", "canonicalSnapshot", "observedAtUTC", "couldNotVerifyKey"],
        ),
        binding(
            SOURCE_PATHS[24], "V23-P02-C07",
            ["WorklightPDFRendererV1"],
            ["WorklightPDFRendererV1", "ObservationBasisV1", "TemporalContextV1", "Observation basis"],
        ),
        binding(
            SOURCE_PATHS[25], "V23-P02-C07",
            ["WholeSignDeletionRule"],
            ["WholeSignDeletionRule", "ObservationAndTimeCodecV1", "validObservationAndTime", "observationBasisV1Data"],
        ),
        binding(
            SOURCE_PATHS[26], "V23-P02-C07",
            ["WholeSignDeletionService"],
            ["WholeSignDeletionService", "exportSnapshot", "observationBasisV1Data", "temporalContextV1Data"],
        ),
        binding(
            SOURCE_PATHS[27], "V23-P02-C07",
            ["CurrentSyncClassificationCatalogV1"],
            ["CurrentSyncClassificationCatalogV1", "semanticBackup", "portableExport", "erase", "searchImplementationPresent"],
        ),
        binding(
            SOURCE_PATHS[28], "V23-P02-C07",
            [
                "ObservationAndTimeValidationFailureV1", "ObservationBasisKindV1",
                "ObservationMethodV1", "ObservationSourceKindV1",
                "ObservationSourceReferenceV1", "ObservationBasisV1",
                "LocalTimeDispositionV1", "TemporalContextV1",
                "ObservationAndTimeSchemaV1", "ObservationAndTimeCodecV1",
                "ObservationAndTimeLegacyMigrationV1",
            ],
            [
                "DIRECTLY_OBSERVED", "REPORTED", "INFERRED", "NOT_OBSERVED",
                "UNVERIFIABLE", "UNKNOWN", "OBSERVER", "REPORTED_PARTY",
                "RECORD", "AMBIGUOUS_FOLD", "NONEXISTENT_GAP",
                "maximumLimitationCount", "maximumEncodedValueBytes",
                "maximumAbsoluteUTCOffsetSeconds", "maximumTimeZoneIdentifierBytes",
                "unknownKey", "sortedKeys", "withoutEscapingSlashes",
                "millisecondsSince1970", "ObservationAndTimeLegacyMigrationV1",
            ],
        ),
        binding(
            SOURCE_PATHS[29], "V23-P02-C07",
            ["S6_2BackupExportTests", "BackupImportService", "BackupExportService"],
            ["S6_2BackupExportTests", "BackupImportService", "stageAndValidate", "importCandidate", "prepareReportDelivery", "backupSchemaVersion", "persistentSchemaVersion", "recordsSchemaVersion", "Canonical", "MutatesNoLiveAuthority"],
        ),
        binding(
            SOURCE_PATHS[30], "V23-P02-C07",
            ["V9_05RestoreIdentityTests", "BackupImportService", "BackupRestoreService"],
            ["V9_05RestoreIdentityTests", "testV9_05G01GoldenEmptyReplaceCloneForkMatrix", "testV9_05A01AlternateBoundedCollisionsAndCrossWorkspace", "testV9_05H01HostileIdentityCollisionAndSourceReplicaReuse", "testV9_05I01CrashPartialActivationCancellationAndLowStorage", "testV9_05R01RecoveryRelaunchAndExportReconciliation", "stageAndValidate", "persistentSchemaVersion", "recordsSchemaVersion", "reconcileAtStartup", "quarantines"],
        ),
        binding(
            SOURCE_PATHS[31], "V23-P02-C07",
            ["V10_03ReplicationConflictRegistryTests", "CurrentSyncClassificationCatalogV1", "ConflictRuleV1", "ConflictPolicyV1", "ConflictIdentityV1", "ReplicationAuthorityV1"],
            ["V10_03ReplicationConflictRegistryTests", "ConflictRuleV1.allCases", "ConflictPolicyV1", "ConflictIdentityV1", "CurrentSyncClassificationCatalogV1", "registeredModelNames.count, 14", "persistentModelNames", "searchImplementationPresent", "secretSubjects", "canonicalKey", "lifecycleRoute", "ReplicationAuthorityV1.allCases"],
        ),
        binding(
            SOURCE_PATHS[32], "V23-P02-C07",
            ["V9_01VersionedSchemaIdentityTests", "PersistentSchemaReleaseV1", "PersistentSchemaMigrationPlanV1"],
            ["V9_01VersionedSchemaIdentityTests", "PersistentSchemaReleaseV1", "PersistentSchemaMigrationPlanV1", "PersistentSchemaMigrationPlanV4", "migrationStage", "migrationPlan: nil", "canonicalData", "receiptHistoryCorrupt"],
        ),
        binding(
            SOURCE_PATHS[33], "V23-P02-C07",
            ["V9_03MigrationRecoveryTests", "StoreMigrationService", "StoreMigrationFailure"],
            ["V9_03MigrationRecoveryTests", "StoreMigrationJournalStoreV1", "migrationCanonicalRecords", "migrationIdentitySource", "migrationFailureInjection", "schemaVersion", "migrationID", "canonicalSHA256"],
        ),
        binding(
            SOURCE_PATHS[34], "V23-P02-C07",
            ["V10_02MutationEnvelopeReceiptTests", "MutationEnvelopeV1", "MutationReceiptV1", "MutationJournalHarnessV1"],
            ["V10_02MutationEnvelopeReceiptTests", "MutationEnvelopeV1", "MutationReceiptV1", "MutationJournalHarnessV1", "EveryAtomicCrashBoundaryRecoversExactlyOnce", "MigrationLifecycle", "canonicalData", "receiptHistoryCorrupt"],
        ),
        binding(
            SOURCE_PATHS[35], "V23-P02-C07",
            ["V9_08GenerationLeaseTests", "GenerationLeaseRegistryV1", "GenerationEpochV1", "GenerationLeaseTokenV1"],
            ["V9_08GenerationLeaseTests", "GenerationLeaseRegistryV1.maximumActiveLeaseCount", "GenerationEpochV1", "GenerationLeaseTokenV1", "reconcileGenerationLeasesAndPrune", "reconcileAbandonedOwners", "BackupImportService", "stageAndValidate", "backupSchemaVersion", "recordsSchemaVersion", "reconcileAtStartup"],
        ),
        binding(
            SOURCE_PATHS[36], "V23-P02-C07",
            TEST_METHODS,
            TEST_METHODS + [
                "ObservationBasisV1", "TemporalContextV1",
                "ObservationAndTimeCodecV1", "MutationJournalFaultBoundaryV1",
                "ObservationAndTimeMigrationV1", "legacy", "backup", "delete",
                "erase", "observationBasisV1Data", "temporalContextV1Data",
            ],
        ),
        binding(
            SOURCE_PATHS[37], "V23-P02-C07",
            ["V21P02C07ObservationTemporalCorpusV1"],
            [
                "fixtureIdentity", "basisKinds", "outcomes", "golden", "alternate",
                "hostileTimeCases", "interruptionBoundaries", "legacyCouldNotVerify",
                "portableLifecycle", "unsupportedSchemaVersion",
            ],
        ),
    ]


def lifecycle_common() -> dict[str, Any]:
    return {
        "persistentContractSchema": "ObservationAndTimeSchemaV1",
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
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
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
    }


def basis_contract() -> dict[str, Any]:
    return seal({
        **base("ObservationBasisContractV1"),
        "owner": "ObservationBasisV1",
        **lifecycle_common(),
        "basis": {
            "schemaVersion": 1,
            "kindEnum": OBSERVATION_BASIS_KINDS,
            "sourceKindEnum": OBSERVATION_SOURCE_KINDS,
            "methodType": "ObservationMethodV1",
            "sourceType": "ObservationSourceReferenceV1",
            "limitationMaximumCount": 16,
            "methodMaximumUTF8Bytes": 128,
            "sourceReferenceMaximumUTF8Bytes": 512,
            "limitationMaximumUTF8Bytes": 2048,
            "sourceRules": {
                "DIRECTLY_OBSERVED": ["OBSERVER"],
                "REPORTED": ["REPORTED_PARTY", "UNKNOWN"],
                "INFERRED": ["RECORD", "UNKNOWN"],
                "NOT_OBSERVED": OBSERVATION_SOURCE_KINDS,
                "UNVERIFIABLE": OBSERVATION_SOURCE_KINDS,
                "UNKNOWN": OBSERVATION_SOURCE_KINDS,
            },
            "outcomeIndependent": True,
            "confidenceFieldPresent": False,
            "directObservationMayBeManufacturedByMigration": False,
            "unknownIsExplicit": True,
            "canonicalCodec": {
                "type": "ObservationAndTimeCodecV1",
                "representation": "Data",
                "sortedKeys": True,
                "withoutEscapingSlashes": True,
                "dateEncoding": "millisecondsSince1970",
                "maximumEncodedValueBytes": 32768,
            },
        },
        "legacyMigration": {
            "type": "ObservationAndTimeLegacyMigrationV1",
            "legacyOutcomeKey": "could_not_verify",
            "legacyReasonKey": "legacy_could_not_verify",
            "legacyMethodKey": "unknown",
            "completeLegacyDisposition": "UNVERIFIABLE",
            "partialLegacyDisposition": "UNKNOWN",
            "emptyLegacyDisposition": "ABSENT",
            "sourceKind": "UNKNOWN",
            "retainsLegacyColumns": True,
            "inventsDirectObservation": False,
        },
        "sourceBindings": [source_bindings()[0], source_bindings()[2], source_bindings()[3], source_bindings()[4], source_bindings()[5], source_bindings()[8], source_bindings()[10], source_bindings()[28]],
        "prohibitedTokens": PROHIBITED_TOKENS + ["confidenceScore", "complianceInference", "noncomplianceInference"],
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def temporal_contract() -> dict[str, Any]:
    return seal({
        **base("TemporalContextContractV1"),
        "owner": "TemporalContextV1",
        **lifecycle_common(),
        "temporal": {
            "schemaVersion": 1,
            "fields": [
                "occurredAtUTC", "recordedAtUTC", "localDate", "localTime",
                "utcOffsetSeconds", "ianaTimeZoneIdentifier", "localTimeDisposition",
            ],
            "dispositionEnum": TIME_DISPOSITIONS,
            "dateEncoding": "millisecondsSince1970",
            "codec": "ObservationAndTimeCodecV1",
            "representation": "Data",
            "canonicalSortedKeys": True,
            "maximumEncodedValueBytes": 32768,
            "validation": [
                "finiteDate",
                "localDateAndLocalTimeArePaired",
                "ISO8601CivilDate",
                "ISO8601CivilTime",
                "capturedUTCOffsetSecondsWithinInclusivePlusOrMinus64800",
                "nonEmptyTrimmedControlFreeTimeZoneIdentifier",
                "timeZoneIdentifierUTF8ByteCountAtMost255",
            ],
            "offsetInclusiveRange": [-64800, 64800],
            "timeZoneIdentifierMaximumUTF8Bytes": 255,
            "liveCreation": {
                "method": "wallTimeRecord(timeZone:)",
                "derivesCurrentOffsetAndDST": True,
                "capturesZoneOffsetAndDisposition": True,
            },
            "durableValidation": {
                "usesCapturedTuple": True,
                "reopensTimeZoneDatabase": False,
                "rederivesOffsetOrDST": False,
            },
            "causalOrdering": "FORBIDDEN",
            "durationMeasurement": "FORBIDDEN",
            "wallClockRollback": "DISPLAY_CONTEXT_ONLY_NO_CAUSAL_REORDER",
            "wallClockForwardJump": "DISPLAY_CONTEXT_ONLY_NO_CAUSAL_REORDER",
            "fold": "PRESERVE_EXPLICIT_AMBIGUOUS_FOLD_WITH_CIVIL_TIME_AND_ZONE",
            "gap": "PRESERVE_EXPLICIT_NONEXISTENT_GAP_WITHOUT_INVENTED_INSTANT",
            "unknown": "RETAIN_UNKNOWN_WITHOUT_TZDB_GUESS",
        },
        "monotonicSeparation": {
            "persistedMonotonicTicks": False,
            "wallClockIsNotMonotonicSource": True,
            "causalAuthority": "acceptedMutationOrder_and_revisions",
        },
        "sourceBindings": [source_bindings()[1], source_bindings()[3], source_bindings()[4], source_bindings()[6], source_bindings()[8], source_bindings()[10], source_bindings()[16], source_bindings()[19], source_bindings()[20], source_bindings()[21], source_bindings()[22], source_bindings()[23], source_bindings()[28]],
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def lifecycle_contract() -> dict[str, Any]:
    return seal({
        **base("ObservationTemporalLifecycleContractV1"),
        "owner": "ObservationAndTimeSchemaV1",
        **lifecycle_common(),
        "lifecycle": {
            "migration": {
                "schemaFrom": "V4",
                "schemaTo": "V5",
                "receiptType": "ObservationAndTimeMigrationReceiptV1",
                "legacyCouldNotVerify": "LOSSLESS_TO_UNVERIFIABLE_OR_UNKNOWN",
                "directObservationFabrication": False,
                "currentBytesWin": True,
                "failureIsRecoverable": True,
            },
            "canonicalMutation": {
                "writer": "WorkspaceWriterAdapterV1",
                "atomicFields": ["content", "revision", "observationBasisV1Data", "temporalContextV1Data", "mutationReceipt"],
                "effectBeforeReceipt": True,
                "partialObservationOrTemporalBytes": False,
                "canonicalCodec": "ObservationAndTimeCodecV1",
            },
            "frozenWorkflowRecord": {
                "model": "WorkflowRecord",
                "noNewFields": True,
                "fieldClosure": [
                    "id", "schemaVersion", "assetID", "packetID", "issueID",
                    "parentRecordID", "recordRevisionRootID", "revisesRecordID",
                    "evidenceSourceRecordID", "revisionKind", "stage", "state",
                    "draftStepKey", "startedAt", "completedAt", "observedAtUTC",
                    "timeZoneID", "utcOffsetMinutes", "localDate", "localTime",
                    "afterDarkAcknowledgementKey", "afterDarkAcknowledgementCopy",
                    "afterDarkAcknowledgementVersion", "afterDarkAcknowledgementAccepted",
                    "safePositionAcknowledgementKey", "safePositionAcknowledgementCopy",
                    "safePositionAcknowledgementVersion", "safePositionAcknowledgementAccepted",
                    "packID", "packSchemaVersion", "packContentVersion", "pdfTemplateID",
                    "pdfTemplateVersion", "outcomeKey", "couldNotVerifyKey",
                    "couldNotVerifyDisplaySnapshot", "couldNotVerifyRegistryVersion",
                    "workPerformedLocalDate", "workDescription", "note", "finalizationMutationID",
                ],
                "companionType": "ObservationAndTimeRow",
                "companionFields": ["observationBasisV1Data", "temporalContextV1Data"],
            },
            "companionLifecycle": {
                "type": "ObservationAndTimeRow",
                "fields": ["observationBasisV1Data", "temporalContextV1Data"],
                "atomicWithWorkflowRecord": True,
                "pairRequired": True,
                "partialPairForbidden": True,
                "canonicalCodec": "ObservationAndTimeCodecV1",
            },
            "reportCorrectionDelivery": {
                "correctionRule": "ReportCorrectionRule",
                "deliveryCoordinator": "ReportDeliveryCoordinator",
                "snapshotSchemaVersion": 2,
                "schema2PathRequired": True,
                "sourceRecordIsFrozen": True,
                "companionFieldsAtomic": ["observationBasisV1Data", "temporalContextV1Data"],
            },
            "importCompatibility": {
                "backupSchemaVersion": 4,
                "persistentSchemaVersion": 5,
                "recordsSchemaVersion": 4,
                "tuple": "4/5/4",
                "service": "BackupImportService",
                "validation": "stageAndValidate",
                "unsupportedOrMalformed": "QUARANTINE_OR_FAIL_CLOSED",
            },
            "modelCountRegression": {
                "persistentModelCount": 14,
                "sourceTest": "V10_03ReplicationConflictRegistryTests",
                "assertion": "registeredModelNames.count == 14",
            },
            "portable": {
                "backup": "ROUND_TRIP_CANONICAL_OBSERVATION_AND_TEMPORAL_BYTES",
                "replaceRestore": "REBUILD_FROM_CANONICAL_INCOMPLETE_INTENTS",
                "clone": "PRESERVE_CANONICAL_BYTES_WITH_NEW_GENERATION_ID",
                "fork": "PRESERVE_CANONICAL_BYTES_WITH_EXPLICIT_FORK_IDENTITY",
                "export": "INCLUDE_CANONICAL_OBSERVATION_AND_TEMPORAL_BYTES",
                "import": "VALIDATE_AND_QUARANTINE_UNSUPPORTED_OR_MALFORMED_BYTES",
                "journalReplay": "REPLAY_IDEMPOTENTLY_WITH_SAME_CANONICAL_BYTES",
                "report": "RENDER_CAPTURED_BASIS_AND_TEMPORAL_CONTEXT",
                "delete": "REMOVE_EMBEDDED_VALUES_ATOMICALLY_WITH_CANONICAL_DELETE",
                "erase": "REMOVE_EMBEDDED_VALUES_ATOMICALLY_WITH_CANONICAL_ERASE",
            },
            "interruptionBoundaries": [
                "afterEffectBeforeReceipt",
                "afterReceiptBeforeSave",
                "afterSaveBeforeReturn",
            ],
            "recovery": {
                "restoreImportReplay": "IDENTICAL_BYTES_OR_QUARANTINE_UNSUPPORTED_VERSION",
                "unknownSchemaVersion": "FAIL_CLOSED_QUARANTINE",
                "corruptEncoding": "FAIL_CLOSED_NO_PARTIAL_SUCCESS",
            },
            "downgrade": {
                "beforeActivation": "DISCARD_UNACTIVATED_DELTA_ONLY",
                "afterActivation": "FORWARD_FIX_PRESERVES_RELEASED_BYTES",
                "unknownEnum": "PRESERVE_OR_QUARANTINE_NEVER_GUESS",
            },
            "search": "NOT_APPLICABLE",
            "diagnostics": "EXCLUDE_CUSTOMER_PAYLOAD",
        },
        "s10Exclusions": {
            "phase10PollingDuringParallelExecution": False,
            "nativeEvidence": False,
            "hostedEvidence": False,
            "physicalEvidence": False,
            "adoptionEnabled": False,
            "acceptanceEnabled": False,
            "releaseReady": False,
            "requiresAcceptedS10_6Reconciliation": True,
        },
        "sourceBindings": source_bindings(),
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def executable_evidence() -> list[dict[str, Any]]:
    test_path = SOURCE_PATHS[36]
    return [
        {
            "case": "OBSERVATION_BASIS_ROUND_TRIP",
            "testPath": test_path,
            "requiredTokens": ["ObservationBasisV1", "ObservationAndTimeCodecV1", "basisKinds", "outcomes"],
        },
        {
            "case": "REPORTED_SOURCE_REMAINS_DISTINCT_FROM_INFERENCE",
            "testPath": test_path,
            "requiredTokens": ["reported", "inferred", "reportedParty", "record", "unknown"],
        },
        {
            "case": "DST_FOLD_GAP_AND_CLOCK_ROLLBACK",
            "testPath": test_path,
            "requiredTokens": ["ambiguousFold", "nonexistentGap", "wall-clock-rollback", "XCTAssertThrowsError"],
        },
        {
            "case": "LEGACY_COULD_NOT_VERIFY_MIGRATION",
            "testPath": test_path,
            "requiredTokens": ["legacy_could_not_verify", "ObservationAndTimeMigrationV1", "unverifiable", "unknown"],
        },
        {
            "case": "ATOMIC_MUTATION_NO_PARTIAL_BYTES",
            "testPath": test_path,
            "requiredTokens": ["afterEffectBeforeReceipt", "afterReceiptBeforeSave", "afterSaveBeforeReturn", "observationBasisV1Data", "temporalContextV1Data"],
        },
        {
            "case": "PORTABLE_LIFECYCLE_CANONICAL_BYTES",
            "testPath": test_path,
            "requiredTokens": ["backup", "restore", "export", "import", "replay", "delete", "erase"],
        },
    ]


def corpus_contract() -> dict[str, Any]:
    return seal({
        **base("ObservationTemporalCorpusManifestV1"),
        "fixturePath": SOURCE_PATHS[37],
        "fixtureSchema": "V21P02C07ObservationTemporalCorpusV1",
        "fixtureSchemaVersion": 1,
        "testPath": SOURCE_PATHS[36],
        "fixtureTopLevelFields": [
            "schemaVersion", "fixtureIdentity", "basisKinds", "outcomes", "golden",
            "alternate", "hostileTimeCases", "interruptionBoundaries",
            "legacyCouldNotVerify", "portableLifecycle", "unsupportedSchemaVersion",
        ],
        "fixtureIdentity": "V21-P02-C07-OBSERVATION-TEMPORAL-CORPUS-V1",
        "fixtureRequiredBasisKinds": [
            "directly_observed", "reported_by_person", "inferred",
            "not_observed", "unverifiable", "unknown",
        ],
        "fixtureRequiredOutcomes": ["compliant", "noncompliant", "unknown"],
        "fixtureRequiredHostileTimeCaseIDs": [
            "fall-fold-first", "fall-fold-second", "spring-gap",
            "unknown-zone", "wall-clock-rollback",
        ],
        "fixtureRequiredInterruptionBoundaries": [
            "afterEffectBeforeReceipt",
            "afterReceiptBeforeSave",
            "afterSaveBeforeReturn",
        ],
        "fixtureRequiredPortableLifecycle": [
            "backup", "replace_restore", "clone", "fork", "export",
            "import", "journal_replay", "delete", "erase",
        ],
        "fixtureLegacyMigration": {
            "outcomeKey": "could_not_verify",
            "expectedCompleteKind": "unverifiable",
            "expectedPartialKind": "unknown",
            "expectedMethod": "unknown",
            "expectedSourceReference": None,
            "directObservationFabricated": False,
        },
        "fixtureUnsupportedSchemaVersion": 2147483647,
        "evidence": [
            {"evidenceID": evidence, "testMethod": method}
            for evidence, method in zip(EVIDENCE_IDS, TEST_METHODS)
        ],
        "requiredCoverage": {
            "G01": [
                "OBSERVATION_BASIS_ROUND_TRIP",
                "ALL_SIX_BASIS_KINDS",
                "OUTCOME_INDEPENDENCE",
            ],
            "A01": [
                "REPORTED_SOURCE_IS_NOT_INFERENCE",
                "BOUNDED_METHOD_SOURCE_AND_LIMITATIONS",
                "EXPLICIT_UNKNOWN_IS_PRESERVED",
            ],
            "H01": [
                "DST_FOLD_AND_NONEXISTENT_GAP",
                "CLOCK_ROLLBACK_NO_CAUSAL_REORDER",
                "UNSUPPORTED_OR_CORRUPT_BYTES_FAIL_CLOSED",
            ],
            "I01": [
                "ATOMIC_MUTATION_BOUNDARIES",
                "NO_PARTIAL_BASIS_OR_TEMPORAL_BYTES",
            ],
            "R01": [
                "BACKUP_RESTORE_CLONE_FORK_IMPORT_EXPORT_REPLAY",
                "DELETE_AND_ERASE_RECONCILE_CANONICAL_BYTES",
                "IDENTICAL_BYTES_OR_QUARANTINE",
                "LEGACY_MIGRATION_NO_DIRECT_OBSERVATION",
            ],
        },
        "executableEvidence": executable_evidence(),
        "hostileFailClosed": True,
        "customerDataPresent": False,
        "secretsPresent": False,
        "fixtureGeneratedByTooling": False,
        "exactFiveTestMethods": True,
        "lifecycle": {
            "persistentChangeMode": "NEW_SCHEMA_VERSION",
            "persistentContractSchema": "ObservationAndTimeSchemaV1",
            "schemaBehaviorDelta": True,
            "migrationBehaviorDelta": True,
            "backupBehaviorDelta": True,
            "restoreBehaviorDelta": True,
            "deleteBehaviorDelta": True,
            "exportBehaviorDelta": True,
            "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
            "legacyCouldNotVerify": "LOSSLESS_UNVERIFIABLE_OR_UNKNOWN_NO_DIRECT_OBSERVATION",
            "canonicalCodec": "ObservationAndTimeCodecV1",
            "portableLifecycle": "CANONICAL_BYTES_OR_QUARANTINE",
            "interruption": "ATOMIC_NO_PARTIAL_BYTES",
            "noPersistedMonotonicTicks": True,
            "noCausalWallClockOrdering": True,
        },
        "s10Exclusions": {
            "nativeCompileRan": False,
            "hostedDispatchRan": False,
            "physicalEvidenceComplete": False,
            "adoptionEnabled": False,
            "acceptanceEnabled": False,
            "releaseReady": False,
            "phase10PollingDuringParallelExecution": False,
            "requiresAcceptedS10_6Reconciliation": True,
        },
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def _strict(value: Any, digest: bool = False) -> dict[str, Any]:
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {
                key: _strict(child, key == "artifactDigest")
                for key, child in value.items()
            },
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
    if digest:
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    if isinstance(value, bool):
        return {"const": value}
    if value is None:
        return {"type": "null"}
    if isinstance(value, int):
        return {"const": value}
    if isinstance(value, str):
        return {"const": value}
    raise ContractError(f"unsupported schema value: {type(value)}")


def schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{value['schema']}.schema.json",
        "title": title,
    })
    return result


def _rows(root: Path, generated: dict[str, bytes]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for relative in MANIFEST_INPUT_PATHS:
        data = generated.get(relative)
        if data is None:
            path = root / relative
            if not path.is_file():
                raise ContractError(f"missing sealed manifest input: {relative}")
            data = path.read_bytes()
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data)})
    return rows


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = _rows(root, generated)
    return seal({
        **base("V23-P02-C07-tooling-manifest"),
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
        "artifactSetDigest": sha(pretty(rows)),
        "fenceProof": {
            "baseHead": APP_BASE_HEAD,
            "baseTree": APP_BASE_TREE,
            "pathFenceDigest": FENCE_DIGEST,
            "allowedDeletePaths": [],
            "allowedRenamePaths": [],
            "priorFenceOverlapCount": 108,
            "authorizedPriorFenceOverlapCount": 108,
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
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    basis = basis_contract()
    temporal = temporal_contract()
    lifecycle = lifecycle_contract()
    corpus = corpus_contract()
    generated = {
        BASIS_SCHEMA: pretty(schema("ObservationBasisContractV1", basis)),
        TEMPORAL_SCHEMA: pretty(schema("TemporalContextContractV1", temporal)),
        LIFECYCLE_SCHEMA: pretty(schema("ObservationTemporalLifecycleContractV1", lifecycle)),
        CORPUS_SCHEMA: pretty(schema("ObservationTemporalCorpusManifestV1", corpus)),
        BASIS_DOC: pretty(basis),
        TEMPORAL_DOC: pretty(temporal),
        LIFECYCLE_DOC: pretty(lifecycle),
        CORPUS_DOC: pretty(corpus),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated

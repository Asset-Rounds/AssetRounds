#!/usr/bin/env python3
"""Deterministic Card 26 lifecycle, storage, and time contracts.

The module is deliberately data first.  Every generated document is an exact
key, Draft 2020-12 projection of its Python value and carries a digest of the
undigested value.  The tooling manifest seals all 26 non-manifest paths in the
hydrated 27-path fence.  No worktree discovery is used to choose contract
values; the worktree is read only for the byte seals in the manifest.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P02-C06"
TITLE = "Protected-data lifecycle, storage pressure, and device-time semantics"

# Immutable hydration authority for the expansion worktree.
APP_BASE_HEAD = "0272a8ffc24af98343fdfbc0b51e5063bd3e1134"
APP_BASE_TREE = "d603f733609dd5d8214ff59bca0b172bb4c770d2"
COORDINATION_HEAD = "9cf025a2b8a99d2aed2822824b245fa84916f0b8"
COORDINATION_TREE = "6dea1d96e3d1fe9cf6656682b6e6b62b2e3ac6bb"
COORDINATION_CAS_SEQUENCE = 104
COORDINATION_LEDGER_DIGEST = "f867bd6467c7287683fbf86a9049dd8609e0c70fa24d2d8b68e1b03f7b87b492"
HYDRATION_PROJECTION_DIGEST = "6c10ad0d12d106c1e3ed09ed731afb143a914acc1595772a3088ad18a09b4d44"
CONTEXT_DIGEST = "862112f0903b8f78834332ef9f089dd91907a8a39b32748ee055c749dd660f86"
FENCE_DIGEST = "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a"
PREREQUISITE_DIGEST = "ca153b318446a7aead005e8f4c510a1c384b093c622efc8d0fb444d003d8e1b0"
TRANSITION_DIGEST = "dbbb09e0cadda8c20dfc64e3dd79e64862b531714538028952f1bf0f416b1c8c"
AUTHORITY_RECEIPT_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"
OVERRIDE_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
REGISTER_ROW_DIGEST = "ce7cb0a63873f41df355e4ec13c2869c98e70438cb42f2a029e2fed7bf6605ea"
DOSSIER_DIGEST = "74cb5ad75992718658327f60b44ab752e2aa4bda09119ddeaf06c7ec1353f443"
INHERITED_DIGEST = "0a7f64772e37775628a9721a280be83c7c0cb389d234672b4f4d7f39861cf7d5"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p02-c06-contracts-v1"
GENERATOR_SEED = 230206

CONTRACT_SCRIPT = "Scripts/v23/p02_c06_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c06_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c06_contracts.py"
LIFECYCLE_SCHEMA = "Scripts/v23/device-lifecycle-boundary.schema.json"
STORAGE_SCHEMA = "Scripts/v23/owned-storage-ledger.schema.json"
TIME_SCHEMA = "Scripts/v23/device-time-semantics.schema.json"
CORPUS_SCHEMA = "Scripts/v23/lifecycle-boundary-corpus.schema.json"
LIFECYCLE_DOC = "docs/design/v23/tooling/V23P02C06DeviceLifecycleBoundaryContractV1.json"
STORAGE_DOC = "docs/design/v23/tooling/V23P02C06OwnedStorageLedgerContractV1.json"
TIME_DOC = "docs/design/v23/tooling/V23P02C06DeviceTimeSemanticsContractV1.json"
CORPUS_DOC = "docs/design/v23/tooling/V23P02C06LifecycleBoundaryCorpusManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C06-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift",
    "FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/System/SystemRuntimeAdapters.swift",
    "FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/LocalJobStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift",
]
SOURCE_PATHS = EXISTING_PATHS + [
    "FieldEvidenceApp/Infrastructure/Persistence/DeviceLifecycleCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift",
    "FieldEvidenceApp/Infrastructure/System/DeviceTimeSemanticsV1.swift",
    "FieldEvidenceAppTests/V9_10LifecycleBoundaryTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Lifecycle/V21P02C06LifecycleBoundaryCorpusV1.json",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    LIFECYCLE_SCHEMA,
    STORAGE_SCHEMA,
    TIME_SCHEMA,
    CORPUS_SCHEMA,
    LIFECYCLE_DOC,
    STORAGE_DOC,
    TIME_DOC,
    CORPUS_DOC,
    MANIFEST,
]
NEW_PATHS = SOURCE_PATHS[len(EXISTING_PATHS):] + TOOL_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = TOOL_PATHS[3:]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_10G01ProtectedDataAndSceneLifecycleMatrix",
    "testV9_10A01LowSpacePreflightRefusesBeforeCanonicalMutation",
    "testV9_10H01LockDuringOperationFailsRecoverablyWithoutPartialSuccess",
    "testV9_10I01BackgroundTerminationAtEveryDurableBoundaryRelaunchesCleanly",
    "testV9_10R01StorageReconciliationAndClockTimezoneDSTRecovery",
]

LIFECYCLE_STATES = [
    "PROTECTED_DATA_AVAILABLE",
    "PROTECTED_DATA_UNAVAILABLE",
    "SCENE_ACTIVE",
    "SCENE_INACTIVE",
    "SCENE_BACKGROUND",
    "RELAUNCH_RECONCILIATION",
    "FAIL_CLOSED",
]
LIFECYCLE_EVENTS = [
    "protectedDataBecameUnavailable",
    "protectedDataBecameAvailable",
    "sceneBecameInactive",
    "sceneEnteredBackground",
    "sceneBecameActive",
]
STORAGE_ROOTS = [
    "FieldEvidenceData",
    "FieldEvidenceRestore",
    "FieldEvidenceOperations",
    "FieldEvidenceErase",
    "FieldEvidenceDiagnostics",
    "FieldEvidenceCommerce",
    "local-jobs-v1",
]
STORAGE_FAILURES = [
    "invalidRoot",
    "duplicateRoot",
    "volumeMismatch",
    "accountingOverflow",
    "entryLimitExceeded",
    "reservationLimitExceeded",
    "depthLimitExceeded",
    "unsupportedEntry",
    "capacityUnavailable",
    "insufficientCapacity",
    "attemptCollision",
]
TIME_CASES = [
    "WALL_CLOCK_ROLLBACK",
    "WALL_CLOCK_FORWARD",
    "TIMEZONE_CONTEXT",
    "DST_FOLD",
    "DST_GAP",
    "MONOTONIC_REGRESSION",
    "DURATION_OVERFLOW",
]
PROHIBITED_TOKENS = [
    "accountID", "authenticatedUserID", "backgroundDaemon", "CloudKit", "CKRecord",
    "inbox", "outbox", "providerID", "remoteProvider", "serverCursor", "serverRevision",
    "tenantID", "vectorClock", "accessToken", "serviceCredential", "secretMaterial",
]


class ContractError(ValueError):
    """Raised when frozen Card26 inputs cannot be generated."""


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


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
        "registerOrdinal": 26,
        "title": TITLE,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "lineageSource": "V21-P02-C06",
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
        "directPrerequisites": ["V23-P02-C05"],
        "invalidationConsumers": ["V23-P02-C07"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema_name: str) -> dict[str, Any]:
    return {"schema": schema_name, "schemaVersion": 1, "cardID": CARD, "authority": authority()}


def source_bindings() -> list[dict[str, Any]]:
    return [
        {
            "path": SOURCE_PATHS[0], "owner": "V23-P02-C06",
            "symbols": ["ApplicationClock", "ApplicationMonotonicInstantV1", "ApplicationMonotonicClockV1"],
            "requiredTokens": ["Wall time for durable records", "never be used to order causal mutations or measure durations", "ApplicationMonotonicInstantV1", "no Codable", "ApplicationMonotonicClockV1"],
        },
        {
            "path": SOURCE_PATHS[1], "owner": "V23-P02-C06",
            "symbols": ["LocalJobLifecycleSuspensionReasonV1", "ResumableLocalJobLifecyclePortV1"],
            "requiredTokens": ["PROTECTED_DATA_UNAVAILABLE", "SCENE_BACKGROUND", "suspendForLifecycle", "resumeAfterLifecycle", "never equivalent to user cancellation"],
        },
        {
            "path": SOURCE_PATHS[2], "owner": "V23-P02-C06",
            "symbols": ["OwnedStorageAttemptIDV1", "OwnedStorageVolumeIdentityV1", "OwnedStorageReservationV1", "WorkspaceStorageAdmissionPortV1"],
            "requiredTokens": ["OwnedStorageAttemptIDV1", "OwnedStorageVolumeIdentityV1", "OwnedStorageReservationV1", "WorkspaceStorageAdmissionPortV1", "storageAdmissionFailed"],
        },
        {
            "path": SOURCE_PATHS[3], "owner": "V23-P02-C06",
            "symbols": ["WorkspaceWriterV1"],
            "requiredTokens": ["storageAdmissionFailed", "WorkspaceStorageAdmissionPortV1", "reserve", "release"],
        },
        {
            "path": SOURCE_PATHS[4], "owner": "V23-P02-C06",
            "symbols": ["SystemApplicationClock", "SystemApplicationMonotonicClockV1"],
            "requiredTokens": ["DispatchTime.now().uptimeNanoseconds", "SystemApplicationMonotonicClockV1"],
        },
        {
            "path": SOURCE_PATHS[5], "owner": "V23-P02-C06",
            "symbols": ["StoragePreflightService"],
            "requiredTokens": ["StoragePreflightService", "capacityUnavailable", "insufficientCapacity"],
        },
        {
            "path": SOURCE_PATHS[6], "owner": "V23-P02-C06",
            "symbols": ["ProtectedFilePolicyV1"],
            "requiredTokens": ["protectedDataUnavailable", "symbolicLink", "O_NOFOLLOW"],
        },
        {
            "path": SOURCE_PATHS[7], "owner": "V23-P02-C05",
            "symbols": ["ResumableLocalJobV1", "LocalJobPendingPublicationV1", "LocalJobPublicationReceiptV1"],
            "requiredTokens": ["AWAITING_PUBLICATION", "pendingPublication", "publicationReceipt", "PUBLISH_OR_ADOPT", "ADOPT_ONLY"],
        },
        {
            "path": SOURCE_PATHS[8], "owner": "V23-P02-C05",
            "symbols": ["LocalJobStoreV1"],
            "requiredTokens": ["resumePending", "markLifecycleSuspended", "resumeAfterProtectedDataAvailable", "markAwaitingPublication", "markPublicationSucceeded", "markPublicationAbsentAndCancelled", "quarantineAndRebuild", "removeJobs", "eraseAll"],
        },
        {
            "path": SOURCE_PATHS[9], "owner": "V23-P02-C05",
            "symbols": ["ResumableLocalJobRunnerV1"],
            "requiredTokens": ["suspendForLifecycle", "resumeAfterLifecycle", "suppressedPublicationRetries", "reconcileForDestructiveRemoval", "generationPublicationAdapter", "awaitingPublication"],
        },
        {
            "path": SOURCE_PATHS[10], "owner": "V23-P02-C06",
            "symbols": ["ProtectedDataLifecycleStateV1", "SceneLifecycleStateV1", "DeviceLifecycleStateV1", "DeviceLifecycleEventV1", "DeviceLifecycleActionV1", "DeviceLifecycleTransitionV1", "DeviceLifecycleReducerV1", "DeviceLifecycleCoordinatorV1"],
            "requiredTokens": ["protectedDataBecameUnavailable", "protectedDataBecameAvailable", "sceneBecameInactive", "sceneEnteredBackground", "sceneBecameActive", "state.scene == .active", "suspendForLifecycle", "resumeAfterLifecycle", "pendingActions", "initiallyConservative", "bootstrap", "fail-closed"],
        },
        {
            "path": SOURCE_PATHS[11], "owner": "V23-P02-C06",
            "symbols": ["OwnedStorageRootKindV1", "OwnedStorageRootV1", "OwnedStorageSnapshotV1", "OwnedStorageLedgerFailureV1", "OwnedStorageLedgerV1"],
            "requiredTokens": ["OwnedStorageRootKindV1", "OwnedStorageRootV1", "OwnedStorageSnapshotV1", "OwnedStorageLedgerFailureV1", "OwnedStorageLedgerV1", "snapshot", "reserve", "release", "reconcile", "reservationLimitExceeded", "maximumScannedEntryCount", "maximumDirectoryDepth", "maximumActiveReservationCount", "O_NOFOLLOW", "AT_SYMLINK_NOFOLLOW", "Storage pressure never authorizes deletion"],
        },
        {
            "path": SOURCE_PATHS[12], "owner": "V23-P02-C06",
            "symbols": ["DeviceTimeSemanticsFailureV1", "DeviceWallTimeRecordV1", "InProcessDurationTokenV1", "DeviceTimeSemanticsV1"],
            "requiredTokens": ["DeviceTimeSemanticsFailureV1", "DeviceWallTimeRecordV1", "InProcessDurationTokenV1", "monotonicClockRegressed", "durationOverflow", "timeZoneIdentifier", "utcOffsetSeconds", "isDaylightSavingTime", "maximumTimeZoneIdentifierUTF8ByteCount", "maximumAbsoluteUTCOffsetSeconds", "trimmingCharacters", "controlCharacters", "timeZoneIdentifier.utf8.count", "wallTimeRecord", "secondsFromGMT", "record.validate"],
        },
        {
            "path": SOURCE_PATHS[13], "owner": "V23-P02-C06",
            "symbols": TEST_METHODS,
            "requiredTokens": TEST_METHODS + ["protectedDataBecameUnavailable", "sceneBecameInactive", "sceneEnteredBackground", "sceneBecameActive", "initiallyConservative", "fail-closed bootstrap must suspend before returning", "capacityUnavailable", "storageAdmissionFailed", "wallClockJumpsSeconds", "monotonicElapsedNanoseconds", "relaunch", "fail closed", "awaitingPublicationEffectBeforeReceipt", "capturedBeforeTZDBDrift", "durable captured tuple must survive later TZDB interpretation drift", "maximumTimeZoneIdentifierUTF8ByteCount", "maximumAbsoluteUTCOffsetSeconds", "foldFirstCivil", "foldSecondCivil"],
        },
        {
            "path": SOURCE_PATHS[14], "owner": "V23-P02-C06",
            "symbols": ["V21P02C06LifecycleBoundaryCorpusV1"],
            "requiredTokens": ["fixtureIdentity", "protectedDataBecameUnavailable", "sceneEnteredBackground", "awaitingPublicationEffectBeforeReceipt", "storage", "timeCases", "wallClockJumpsSeconds", "monotonicElapsedNanoseconds"],
        },
    ]


def lifecycle_contract() -> dict[str, Any]:
    return seal({
        **base("DeviceLifecycleBoundaryContractV1"),
        "owner": "DeviceLifecycleCoordinatorV1",
        "persistentContractSchema": "PROTECTED_DATA_STORAGE_PRESSURE_AND_DEVICE_TIME_SEMANTICS_V1",
        "persistentChangeMode": "CONTENT_ONLY",
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": False,
        "exportBehaviorDelta": False,
        "lifecycle": {
            "states": LIFECYCLE_STATES,
            "events": LIFECYCLE_EVENTS,
            "initialState": {"protectedData": "UNAVAILABLE", "scene": "INACTIVE"},
            "reducer": "DeviceLifecycleReducerV1",
            "bootstrap": {
                "method": "DeviceLifecycleCoordinatorV1.bootstrap",
                "defaultInitialState": "initiallyConservative",
                "protectedDataUnavailableSuspendedBeforeReturn": True,
                "backgroundSuspendedBeforeReturn": True,
            },
            "reducerBehavior": {
                "sceneBecameActiveFromAnyNonActiveState": "RESUME_SCENE_BACKGROUND",
                "sceneBecameActiveFromActiveState": "NONE",
            },
            "stateTruthPreservedWhenRecoveryBlocked": True,
            "sameEdgeIsIdempotent": True,
            "actions": ["NONE", "SUSPEND_PROTECTED_DATA", "RESUME_PROTECTED_DATA", "SUSPEND_SCENE_BACKGROUND", "RESUME_SCENE_BACKGROUND"],
            "suspensionReasons": ["PROTECTED_DATA_UNAVAILABLE", "SCENE_BACKGROUND"],
            "suspensionIsNotUserCancellation": True,
            "protectedData": {
                "unavailableBlocksBeforeEffect": True,
                "failureHook": "protectedDataFailureHook",
                "availableRequeuesOnlyAfterDurableStoreReadback": True,
                "noPartialCanonicalSuccess": True,
            },
            "scene": {
                "inactiveIsObservedWithoutSuspension": True,
                "backgroundSuspendsLifecycleWork": True,
                "activeResumesAfterDurableReadback": True,
                "optionalBackgroundTokenAcceleration": False,
            },
            "relaunch": {
                "reconcileStateBeforeResume": True,
                "runningRowsRequeue": True,
                "cancellationRequestedRowsCancelWithoutPublication": True,
                "awaitingPublicationAdoptsExactReadback": True,
                "effectBeforeReceipt": "ADOPT_ONLY_OR_PUBLISH_OR_ADOPT_EXACT_READBACK",
                "noSpinOnSuppressedPublicationRetry": True,
            },
            "failClosed": {
                "unknownOrCorruptOperationalState": "QUARANTINE_DELETE_AND_RECONSTRUCT",
                "protectedDataDenial": "VISIBLE_BLOCKED_STATE_NO_EFFECT",
                "storageAdmissionFailure": "VISIBLE_FAILURE_BEFORE_CANONICAL_MUTATION",
                "ambiguousDestructiveRemoval": "RETAIN_OPERATIONAL_ROW",
            },
        },
        "interruptionBoundaries": [
            "BEFORE_PROTECTED_DATA_EFFECT",
            "AFTER_DURABLE_CHECKPOINT",
            "SCENE_BACKGROUND",
            "PROCESS_RELAUNCH",
            "EFFECT_BEFORE_PUBLICATION_RECEIPT",
            "BEFORE_DESTRUCTIVE_REMOVE",
        ],
        "backupRestore": {
            "operationalStateIncludedInUserBackup": False,
            "operationalStateIncludedInUserExport": False,
            "restoreRebuildsFromCanonicalIncompleteIntents": True,
            "canonicalContentSurvivalAuthority": True,
            "deviceLocalReservationsReconstructed": True,
        },
        "sourceBindings": source_bindings(),
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def storage_contract() -> dict[str, Any]:
    return seal({
        **base("OwnedStorageLedgerContractV1"),
        "owner": "OwnedStorageLedgerV1",
        "persistentContractSchema": "PROTECTED_DATA_STORAGE_PRESSURE_AND_DEVICE_TIME_SEMANTICS_V1",
        "persistentChangeMode": "CONTENT_ONLY",
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "rootKinds": STORAGE_ROOTS,
        "rootIdentity": {
            "closedSet": True,
            "parentDirectory": "applicationSupportURL",
            "fileURLsOnly": True,
            "lastPathComponentMustMatchKind": True,
            "sameVolumeRequired": True,
            "duplicateRootDisposition": "FAIL_CLOSED",
        },
        "accounting": {
            "snapshotType": "OwnedStorageSnapshotV1",
            "volumeIdentityType": "OwnedStorageVolumeIdentityV1",
            "attemptIDType": "OwnedStorageAttemptIDV1",
            "reservationType": "OwnedStorageReservationV1",
            "byteType": "Int64_NONNEGATIVE",
            "maximumScannedEntryCount": 100000,
            "maximumDirectoryDepth": 64,
            "maximumActiveReservationCount": 10000,
            "regularFilesOnly": True,
            "symlinksRejected": True,
            "hardLinksRejected": True,
            "deviceChangesRejected": True,
            "overflowFailsClosed": True,
        },
        "admission": {
            "port": "WorkspaceStorageAdmissionPortV1",
            "methods": ["reserve", "release"],
            "preflightBeforeCanonicalMutation": True,
            "attemptReservationIsIdempotent": True,
            "attemptCollisionFailsClosed": True,
            "capacityUnavailableFailure": "capacityUnavailable",
            "insufficientCapacityFailure": "insufficientCapacity",
            "writerFailure": "storageAdmissionFailed",
            "releaseIsIdempotent": True,
            "reservationsAreProcessLocal": True,
        },
        "reconciliation": {
            "method": "reconcile",
            "scansActualOwnedBytes": True,
            "adoptsOnlySuppliedActiveReservations": True,
            "rechecksVolumeIdentity": True,
            "unknownOrCorruptEntry": "FAIL_CLOSED",
            "noAutomaticUserDataDeletion": True,
            "noDeletionForSpace": True,
            "noPersistentReservationStore": True,
            "relaunchRebuildsLedger": True,
        },
        "failureKinds": STORAGE_FAILURES,
        "destructiveOperations": {
            "workspaceDelete": "CANONICAL_OWNER_RECONCILES_THEN_REMOVES_OPERATIONAL_ROWS",
            "eraseAll": "CANONICAL_ERASE_OWNER_RECONCILES_THEN_REMOVES_OPERATIONAL_ROWS",
            "ambiguousPublication": "FAIL_CLOSED_RETAIN_ROW",
            "automaticDataDeletion": False,
        },
        "backupRestore": {
            "ledgerIncludedInUserBackup": False,
            "ledgerIncludedInUserExport": False,
            "restoreRebuildsFromCanonicalTruth": True,
            "reservationsNeverBecomeCanonical": True,
        },
        "sourceBindings": [source_bindings()[2], source_bindings()[3], source_bindings()[5], source_bindings()[11]],
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def time_contract() -> dict[str, Any]:
    return seal({
        **base("DeviceTimeSemanticsContractV1"),
        "owner": "DeviceTimeSemanticsV1",
        "persistentContractSchema": "PROTECTED_DATA_STORAGE_PRESSURE_AND_DEVICE_TIME_SEMANTICS_V1",
        "persistentChangeMode": "CONTENT_ONLY",
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "wallTime": {
            "port": "ApplicationClock",
            "recordType": "DeviceWallTimeRecordV1",
            "durableUses": ["display", "historic_evidence", "timezone_and_dst_context"],
            "causalOrdering": "FORBIDDEN",
            "durationMeasurement": "FORBIDDEN",
            "fields": ["recordedAtUTC", "timeZoneIdentifier", "utcOffsetSeconds", "isDaylightSavingTime"],
            "validation": ["finiteDate", "nonEmptyTrimmedControlFreeZoneIdentifier", "zoneIdentifierUTF8ByteCountAtMost255", "offsetSecondsWithinInclusivePlusOrMinus64800"],
            "zoneIdentifierMaximumUTF8ByteCount": 255,
            "offsetSecondsInclusiveRange": [-64800, 64800],
            "liveCreation": {
                "method": "wallTimeRecord(timeZone:)",
                "derivesCurrentOffset": True,
                "derivesCurrentDST": True,
                "validatesCapturedTuple": True,
            },
            "durableValidation": {
                "usesCapturedTuple": True,
                "reopensTimeZoneDatabase": False,
                "rederivesOffsetOrDST": False,
            },
            "rollbackDisposition": "DISPLAY_CONTEXT_ONLY_NO_CAUSAL_REORDER",
            "forwardJumpDisposition": "DISPLAY_CONTEXT_ONLY_NO_CAUSAL_REORDER",
        },
        "monotonicDuration": {
            "port": "ApplicationMonotonicClockV1",
            "instantType": "ApplicationMonotonicInstantV1",
            "durationTokenType": "InProcessDurationTokenV1",
            "injected": True,
            "processLocal": True,
            "persisted": False,
            "codable": False,
            "regressionFailure": "monotonicClockRegressed",
            "overflowFailure": "durationOverflow",
            "durationUnit": "nanoseconds",
            "systemAdapter": "SystemApplicationMonotonicClockV1",
            "systemSource": "DispatchTime.now().uptimeNanoseconds",
        },
        "timeZoneAndDST": {
            "zoneIdentifierPersistedWithRecord": True,
            "offsetPersistedWithRecord": True,
            "dstContextPersistedWithRecord": True,
            "calendarTransitionsDoNotOrderMutations": True,
        },
        "sourceBindings": [source_bindings()[0], source_bindings()[4], source_bindings()[12]],
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def executable_evidence() -> list[dict[str, Any]]:
    return [
        {"case": "PROTECTED_DATA_LIFECYCLE_HOOK", "testPath": SOURCE_PATHS[13], "requiredTokens": ["protectedDataBecameUnavailable", "protectedDataBecameAvailable", "sceneBecameInactive", "sceneBecameActive", "initiallyConservative", "suspendForLifecycle", "resumeAfterLifecycle"]},
        {"case": "STORAGE_ADMISSION_BEFORE_CANONICAL_MUTATION", "testPath": SOURCE_PATHS[13], "requiredTokens": ["storageAdmissionFailed", "canonicalMutationAllowanceBytes", "capacityUnavailable"]},
        {"case": "RELAUNCH_CANCELLATION_CLEANUP", "testPath": SOURCE_PATHS[13], "requiredTokens": ["relaunch", "awaitingPublicationEffectBeforeReceipt", "fail-closed"]},
        {"case": "HOSTILE_SYMLINK_CLEANUP", "testPath": SOURCE_PATHS[13], "requiredTokens": ["hostile-symlink", "O_NOFOLLOW", "AT_SYMLINK_NOFOLLOW"]},
        {"case": "DESTRUCTIVE_REMOVE_RECONCILIATION", "testPath": SOURCE_PATHS[13], "requiredTokens": ["removeJobs", "eraseAll", "reconcileForDestructiveRemoval", "fail-closed"]},
        {"case": "WALL_CLOCK_AND_MONOTONIC_SEPARATION", "testPath": SOURCE_PATHS[13], "requiredTokens": ["wallClockJumpsSeconds", "monotonicElapsedNanoseconds", "timeCases", "capturedBeforeTZDBDrift", "foldFirstCivil", "foldSecondCivil"]},
    ]


def corpus_contract() -> dict[str, Any]:
    return seal({
        **base("LifecycleBoundaryCorpusManifestV1"),
        "fixturePath": SOURCE_PATHS[14],
        "fixtureSchema": "V21P02C06LifecycleBoundaryCorpusV1",
        "fixtureSchemaVersion": 1,
        "testPath": SOURCE_PATHS[13],
        "fixtureTopLevelFields": ["schemaVersion", "fixtureIdentity", "lifecycleEvents", "durableBoundaries", "storage", "timeCases", "wallClockJumpsSeconds", "monotonicElapsedNanoseconds"],
        "fixtureRequiredLifecycleEvents": LIFECYCLE_EVENTS,
        "fixtureRequiredDurableBoundaries": ["queuedBeforeClaim", "runningAfterCheckpoint", "awaitingPublicationEffectBeforeReceipt", "terminalSucceeded"],
        "fixtureStorageFields": ["canonicalMutationAllowanceBytes", "ownedFileBytes", "reservationBytes"],
        "fixtureTimeCaseFields": ["utc", "zone", "offset", "dst"],
        "fixtureRequiredTimeCases": [
            {"utc": "2026-01-15T17:00:00Z", "zone": "America/New_York", "offset": -18000, "dst": False},
            {"utc": "2026-07-15T16:00:00Z", "zone": "America/New_York", "offset": -14400, "dst": True},
            {"utc": "2026-03-08T06:59:59Z", "zone": "America/New_York", "offset": -18000, "dst": False},
            {"utc": "2026-03-08T07:00:00Z", "zone": "America/New_York", "offset": -14400, "dst": True},
            {"utc": "2026-11-01T05:00:00Z", "zone": "America/New_York", "offset": -14400, "dst": True},
            {"utc": "2026-11-01T06:00:00Z", "zone": "America/New_York", "offset": -18000, "dst": False},
            {"utc": "2026-07-15T16:00:00Z", "zone": "Pacific/Auckland", "offset": 43200, "dst": False},
        ],
        "fixtureRequiredWallClockJumpsSeconds": [-86400, 259200],
        "fixtureRequiredMonotonicElapsedNanoseconds": 250000000,
        "evidence": [{"evidenceID": evidence, "testMethod": method} for evidence, method in zip(EVIDENCE_IDS, TEST_METHODS)],
        "requiredCoverage": {
            "G01": ["PROTECTED_DATA_STATE_REDUCER", "SCENE_ACTIVE_INACTIVE_BACKGROUND", "LIFECYCLE_SUSPENSION_NOT_USER_CANCELLATION"],
            "A01": ["STORAGE_PREFLIGHT", "NO_CANONICAL_MUTATION_ON_ADMISSION_FAILURE", "REFUSAL_BEFORE_CANONICAL_MUTATION"],
            "H01": ["PROTECTED_DATA_LOCK_INTERRUPTION", "HOSTILE_SYMLINK_FAIL_CLOSED", "STALE_RESUME_NEW_SUSPEND"],
            "I01": ["DURABLE_BOUNDARY_TERMINATION_RELAUNCH", "EFFECT_BEFORE_RECEIPT_ADOPTION", "DESTRUCTIVE_ADOPT_ONLY_RECONCILIATION"],
            "R01": ["STORAGE_RECONCILIATION_AND_RESERVATION_RACE", "WALL_CLOCK_ROLLBACK_FORWARD", "TIMEZONE_DST_AND_MONOTONIC_CLOCK_JUMPS"],
        },
        "executableEvidence": executable_evidence(),
        "hostileFailClosed": True,
        "customerDataPresent": False,
        "secretsPresent": False,
        "fixtureGeneratedByTooling": False,
        "exactFiveTestMethods": True,
        "lifecycle": {
            "persistentChangeMode": "CONTENT_ONLY",
            "schemaBehaviorDelta": False,
            "migrationBehaviorDelta": False,
            "operationalJobStore": "SEPARATELY_VERSIONED_DEVICE_LOCAL_RECONSTRUCTABLE",
            "userBackupAndExport": "EXCLUDED",
            "replaceRestore": "REBUILD_FROM_CANONICAL_INCOMPLETE_INTENTS",
            "workspaceDeleteEraseExpiry": "RECONCILE_THEN_REMOVE_OPERATIONAL_ROWS",
            "downgrade": "FORWARD_FIX_ONLY",
            "noPersistedMonotonicTicks": True,
            "noDeletionForSpace": True,
            "publication": "AWAITING_PUBLICATION_RECONCILES_EFFECT_BEFORE_RECEIPT",
            "publicationFailure": "SUPPRESS_RETRY_NO_SPIN",
            "destructiveRemoval": "FAIL_CLOSED_UNTIL_RECONCILED",
        },
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def _strict(value: Any, digest: bool = False) -> dict[str, Any]:
    """Project a concrete value into an exact-key Draft 2020-12 schema."""
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {key: _strict(child, key == "artifactDigest") for key, child in value.items()},
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
        **base("V23-P02-C06-tooling-manifest"),
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
            "priorFenceOverlapCount": 15,
            "authorizedPriorFenceOverlapCount": 15,
            "unauthorizedPriorFenceOverlapCount": 0,
            "activeS10ReservationDigest": RESERVATION_DIGEST,
            "activeS10Overlap": False,
        },
        "persistentChangeMode": "CONTENT_ONLY",
        "persistentSchemaActivatedByTooling": False,
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "noPersistedMonotonicTicks": True,
        "noDeletionForSpace": True,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    lifecycle = lifecycle_contract()
    storage = storage_contract()
    time = time_contract()
    corpus = corpus_contract()
    generated = {
        LIFECYCLE_SCHEMA: pretty(schema("DeviceLifecycleBoundaryContractV1", lifecycle)),
        STORAGE_SCHEMA: pretty(schema("OwnedStorageLedgerContractV1", storage)),
        TIME_SCHEMA: pretty(schema("DeviceTimeSemanticsContractV1", time)),
        CORPUS_SCHEMA: pretty(schema("LifecycleBoundaryCorpusManifestV1", corpus)),
        LIFECYCLE_DOC: pretty(lifecycle),
        STORAGE_DOC: pretty(storage),
        TIME_DOC: pretty(time),
        CORPUS_DOC: pretty(corpus),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated

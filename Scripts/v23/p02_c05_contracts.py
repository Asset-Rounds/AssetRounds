#!/usr/bin/env python3
"""Deterministic provisional contracts for V23-P02-C05.

This module is intentionally data-first.  The four generated documents are
sealed, exact-key contracts and the four generated schemas are strict
Draft-2020-12 projections of those documents.  The tooling manifest binds the
whole hydrated fence (source and tooling paths) by byte count and SHA-256;
there is no "best effort" or absent-source mode.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P02-C05"
TITLE = "Off-main resumable local jobs, cancellation, concurrency, and scale budgets"

# These values are the immutable C05 bootstrap context/fence, not values
# discovered from a mutable worktree at generation time.
APP_BASE_HEAD = "a6742867a235ad7cc4e4bc07f2b650cca82434cd"
APP_BASE_TREE = "fc0d86d8d02fc463621540637321d4645ad727f8"
COORDINATION_HEAD = "a02692c9f20c6fe4944c7771dde6dd9bdcd51a71"
COORDINATION_TREE = "f326ad839c04b312bb07cbdba17953c6a10237f6"
COORDINATION_CAS_SEQUENCE = 101
COORDINATION_LEDGER_DIGEST = "1cd7e2f90d12258b9e079c650d40d4ce4cee1f22a6b28970167883a26f6d3916"
HYDRATION_PROJECTION_DIGEST = "65d096f19e97ee8b8bdc52a297d58510a57397b952ec9da02432b23ba9145fb2"
CONTEXT_DIGEST = "625a596b0bd0f67c4ca83befe0b05309f35535c9db70584ff9bef3df87bdacaa"
FENCE_DIGEST = "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac"
PREREQUISITE_DIGEST = "9da050851718d6877bb678614f014e657e60868fa9160a62a3a5778da7776d1b"
TRANSITION_DIGEST = "620971c0df32ad82017122d3c81a73f2edec048196412a4454ad8be2a3f6e5d1"
AUTHORITY_RECEIPT_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"
OVERRIDE_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
REGISTER_ROW_DIGEST = "59877398b77b4aefa0bd64678165c52939906eb97bc82e0f9288704366f8f283"
DOSSIER_DIGEST = "ec42ff8d9671a79c44c9d20d861958771689e6b391e00de2d6527dac31e206fe"
INHERITED_DIGEST = "2d967b801e515707b91344039ceb22c2dad717847cb297f05b4fddb510e6989b"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p02-c05-contracts-v1"
GENERATOR_SEED = 230205

CONTRACT_SCRIPT = "Scripts/v23/p02_c05_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c05_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c05_contracts.py"
JOB_SCHEMA = "Scripts/v23/resumable-local-job.schema.json"
STORE_SCHEMA = "Scripts/v23/local-job-store.schema.json"
BUDGET_SCHEMA = "Scripts/v23/concurrency-scale-budget.schema.json"
CORPUS_SCHEMA = "Scripts/v23/concurrency-scale-corpus.schema.json"
JOB_DOC = "docs/design/v23/tooling/V23P02C05ResumableLocalJobContractV1.json"
STORE_DOC = "docs/design/v23/tooling/V23P02C05LocalJobStoreLifecycleContractV1.json"
BUDGET_DOC = "docs/design/v23/tooling/V23P02C05ConcurrencyScaleBudgetPolicyV1.json"
CORPUS_DOC = "docs/design/v23/tooling/V23P02C05ConcurrencyScaleCorpusManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C05-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Application/Ports/DeterministicAsyncPorts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceAppTests/V23_P00_C11MailComposerConcurrencyTests.swift",
]
SOURCE_PATHS = EXISTING_PATHS + [
    "FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/LocalJobStoreSchemaV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/LocalJobStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/JobScaleBudgetPolicyV1.swift",
    "FieldEvidenceAppTests/V9_09ConcurrencyScaleTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Concurrency/V21P02C05ConcurrencyScaleCorpusV1.json",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    JOB_SCHEMA,
    STORE_SCHEMA,
    BUDGET_SCHEMA,
    CORPUS_SCHEMA,
    JOB_DOC,
    STORE_DOC,
    BUDGET_DOC,
    CORPUS_DOC,
    MANIFEST,
]
NEW_PATHS = SOURCE_PATHS[len(EXISTING_PATHS):] + TOOL_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = TOOL_PATHS[3:]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_09G01OffMainWorkersAndDeterministicIdentifiers",
    "testV9_09A01DurableBoundedCheckpointsResumeAfterRelaunch",
    "testV9_09H01StructuredCancellationCleansStagingWithoutPublishingPartialBytes",
    "testV9_09I01GenerationLeaseFencesStalePublicationAndBalancesConcurrency",
    "testV9_09R01RepresentativeScaleMatrixMeetsBoundedConcurrencyMemoryAndLatencyBudgets",
]
OPERATION_KINDS = [
    "HASH", "COPY", "SANITIZE", "RENDER", "ARCHIVE", "IMPORT", "FINALIZE",
    "SEARCH_REBUILD", "STARTER_INSTALLATION", "MEDIA_PROCESSING",
    "RESOURCE_PROJECTION", "SCHEDULE_GENERATION",
]
JOB_STATES = [
    "QUEUED", "RUNNING", "CANCELLATION_REQUESTED", "BLOCKED_PROTECTED_DATA",
    "AWAITING_PUBLICATION", "SUCCEEDED", "FAILED", "CANCELLED",
]
RETRY_CLASSIFICATIONS = [
    "RETRYABLE", "PROTECTED_DATA_UNAVAILABLE", "GENERATION_LEASE_LOST", "PERMANENT",
]
PUBLICATION_MODES = ["PUBLISH_OR_ADOPT", "ADOPT_ONLY"]
PUBLICATION_DISPOSITIONS = ["PUBLISHED", "ADOPTED"]
PROHIBITED_TOKENS = [
    "accountID", "authenticatedUserID", "backgroundDaemon", "CloudKit", "CKRecord",
    "inbox", "outbox", "providerID", "remoteProvider", "serverCursor", "serverRevision",
    "tenantID", "vectorClock", "accessToken", "serviceCredential", "secretMaterial",
]


class ContractError(ValueError):
    """Raised when the frozen C05 contract inputs cannot be generated."""


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
        "registerOrdinal": 25,
        "title": TITLE,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "lineageSource": "V21-P02-C05",
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
        "directPrerequisites": ["V23-P00-C08", "V23-P02-C04"],
        "invalidationConsumers": ["V23-P02-C06"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema_name: str) -> dict[str, Any]:
    return {"schema": schema_name, "schemaVersion": 1, "cardID": CARD, "authority": authority()}


def source_bindings() -> list[dict[str, Any]]:
    return [
        {
            "path": SOURCE_PATHS[17],
            "owner": "V23-P02-C05",
            "symbols": ["ResumableLocalJobPortV1", "ResumableLocalJobOperationV1", "ResumableLocalJobExecutionContextV1", "ResumableLocalJobResultV1", "ResumableLocalJobPublisherV1", "ResumableLocalJobPublicationAuthorityV1", "GenerationLocalJobPublicationAdapterV1"],
            "requiredTokens": ["cancellationBoundary", "validateGenerationLease", "publicationBoundary", "publishOrAdopt", "adoptOnly", "ResumableLocalJobPublisherV1", "ResumableLocalJobPublicationAuthorityV1", "GenerationLocalJobPublicationAdapterV1", "GenerationEpochV1", "currentGenerationEpoch", "withAuthorizedCommit", "effectAndReadback", "@Sendable"],
        },
        {
            "path": SOURCE_PATHS[18],
            "owner": "V23-P02-C05",
            "symbols": ["LocalJobIDV1", "LocalJobChunkIDV1", "ResumableLocalJobV1", "LocalJobCheckpointV1", "LocalJobStateV1", "LocalJobRetryClassificationV1", "LocalJobPendingPublicationV1", "LocalJobPublicationReceiptV1"],
            "requiredTokens": ["deterministic", "immutableInputSHA256", "checkpoint", "generationEpoch", "permitsTransition", "AWAITING_PUBLICATION", "pendingPublication", "publicationReceipt", "PUBLISH_OR_ADOPT", "ADOPT_ONLY", "LocalJobPendingPublicationV1", "LocalJobPublicationReceiptV1"],
        },
        {
            "path": SOURCE_PATHS[19],
            "owner": "V23-P02-C05",
            "symbols": ["LocalJobStoreSchemaV1", "LocalJobStoreEnvelopeV1", "LocalJobStoreMigrationReceiptV1"],
            "requiredTokens": ["currentVersion", "maximumJobCount", "maximumStoreBytes", "includedInUserBackup = false", "restoreRebuildsFromCanonicalIncompleteIntents = true", "quarantinedAndRebuilt"],
        },
        {
            "path": SOURCE_PATHS[20],
            "owner": "V23-P02-C05",
            "symbols": ["LocalJobStoreV1", "resumePending", "saveCheckpoint", "markSucceeded", "markAwaitingPublication", "markPublicationSucceeded", "markPublicationAbsentAndCancelled", "markCancelled", "markFailed"],
            "requiredTokens": ["actor LocalJobStoreV1", ".atomic", ".completeFileProtection", "isExcludedFromBackup", "protectedDataFailureHook", "injectProtectedDataFailure", "quarantineAndRebuild", "O_NOFOLLOW", "AT_SYMLINK_NOFOLLOW", "markAwaitingPublication", "markPublicationSucceeded", "markPublicationAbsentAndCancelled", "pendingPublication", "publicationReceipt"],
        },
        {
            "path": SOURCE_PATHS[21],
            "owner": "V23-P02-C05",
            "symbols": ["ResumableLocalJobRunnerV1", "ResumableLocalJobRunnerFailureV1"],
            "requiredTokens": ["maximumConcurrency", "activeTasks", "Task.checkCancellation", "GenerationLeaseHandleV1", "cleanupStaging", "scheduleAvailableWork", "suppressedPublicationRetries", "reconcilePublication", "reconcileForDestructiveRemoval", "generationPublicationAdapter", "generationPublicationAdapter.publish", "if job.generationEpoch != nil, generationPublicationAdapter == nil", "func removeJobs(workspaceID: UUID) async throws", "func eraseAll() async throws", "try await reconcileForDestructiveRemoval(workspaceID: workspaceID)", "try await reconcileForDestructiveRemoval(workspaceID: nil)", "guard terminal.allSatisfy({ $0.state.isTerminal })", ".awaitingPublication", ".publishOrAdopt", ".adoptOnly"],
        },
        {
            "path": SOURCE_PATHS[22],
            "owner": "V23-P02-C05",
            "symbols": ["JobScaleFixtureV1", "JobScaleBudgetV1", "JobScaleBudgetPolicyV1"],
            "requiredTokens": ["maximumRunnerConcurrency", "oneAsset", "hundredAssets", "tenThousandAssets", "largeMediaProxy", "p95LatencyMilliseconds"],
        },
        {
            "path": SOURCE_PATHS[23],
            "owner": "V23-P02-C05",
            "symbols": TEST_METHODS,
            "requiredTokens": TEST_METHODS + ["enqueued", "finish", "latenciesMilliseconds", "maximumHeartbeatMilliseconds", "completedJobIDs", "hangCount", "published", "protectedDataFailureHook", "protectedDataUnavailable", "corruptBytes", "quarantinedAndRebuilt", "quarantineDirectoryName", "resumePending", "interruptedStagingURL", "relaunch-cancel", "createSymbolicLink", "hostile-symlink", "outsideSentinel", "symlink staging cleanup must fail closed", "removeJobs(workspaceID:", "eraseAll()", "awaitingRemove", "awaitingErase"],
        },
        {
            "path": SOURCE_PATHS[24],
            "owner": "V23-P02-C05",
            "symbols": ["V21P02C05ConcurrencyScaleCorpusV1"],
            "requiredTokens": ["ASSET_1", "ASSET_100", "ASSET_10000", "LARGE_MEDIA_PROXY"],
        },
    ]


def job_contract() -> dict[str, Any]:
    transitions = [
        {"from": state, "to": allowed}
        for state, allowed in (
            ("QUEUED", ["QUEUED", "RUNNING", "CANCELLATION_REQUESTED"]),
            ("RUNNING", ["RUNNING", "QUEUED", "CANCELLATION_REQUESTED", "BLOCKED_PROTECTED_DATA", "AWAITING_PUBLICATION", "FAILED"]),
            ("CANCELLATION_REQUESTED", ["CANCELLATION_REQUESTED", "AWAITING_PUBLICATION", "CANCELLED"]),
            ("BLOCKED_PROTECTED_DATA", ["BLOCKED_PROTECTED_DATA", "QUEUED", "CANCELLATION_REQUESTED"]),
            ("AWAITING_PUBLICATION", ["AWAITING_PUBLICATION", "SUCCEEDED", "CANCELLED"]),
            ("SUCCEEDED", ["SUCCEEDED"]),
            ("FAILED", ["FAILED", "QUEUED"]),
            ("CANCELLED", ["CANCELLED"]),
        )
    ]
    return seal({
        **base("ResumableLocalJobContractV1"),
        "owner": "ResumableLocalJobV1",
        "persistentContractSchema": "RESUMABLE_LOCAL_JOB_SCHEMA_V1",
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "declarationOwners": ["ResumableLocalJobV1", "LocalJobCheckpointV1", "LocalJobStoreMigrationReceiptV1"],
        "operationKinds": OPERATION_KINDS,
        "states": JOB_STATES,
        "retryClassifications": RETRY_CLASSIFICATIONS,
        "identity": {
            "jobID": {
                "algorithm": "SHA256_TRUNCATED_UUID_V5_STYLE",
                "material": ["local-job-v1", "kind.rawValue", "workspaceID.uuidString.lowercased", "immutableInputSHA256"],
                "versionNibble": 5,
                "stableAcrossRetry": True,
                "arrivalOrderOrWallClock": False,
            },
            "chunkID": {
                "algorithm": "SHA256_HEX",
                "material": ["local-job-chunk-v1", "jobID.uuidString.lowercased", "chunkIndex"],
                "stableAcrossRetry": True,
                "zeroBasedIndex": True,
            },
            "immutableInputSHA256": "LOWERCASE_SHA256_REQUIRED",
            "generationEpoch": "OPTIONAL_GENERATION_EPOCH_READER_LEASE",
            "stagingRelativePath": "SAFE_NONEMPTY_RELATIVE_PATH_NO_DOT_SEGMENTS",
            "outputSHA256": "SUCCESS_ONLY_LOWERCASE_SHA256",
        },
        "checkpoint": {
            "schemaVersion": 1,
            "fields": ["schemaVersion", "nextChunkIndex", "completedUnitCount", "totalUnitCount", "lastChunkID", "rollingOutputSHA256"],
            "durableBeforeContinuation": True,
            "completedUnitCountMonotonic": True,
            "nextChunkIndexMonotonic": True,
            "completedAtMostTotal": True,
            "lastChunkIDBindsPreviousChunk": True,
            "rollingOutputSHA256OptionalLowercase": True,
            "resumeSource": "DURABLE_LOCAL_JOB_STORE_ONLY",
        },
        "execution": {
            "workerIsolation": "OFF_MAIN_ACTOR_OR_STRUCTURED_TASK",
            "uiActorFileHashRenderArchiveWork": "FORBIDDEN",
            "maximumConcurrentJobs": 2,
            "backpressure": "BOUNDED_ACTIVE_TASK_SET_AND_QUEUE",
            "oneTaskPerJob": True,
            "childTaskOwnership": "RUNNER_ACTOR_RETAINS_AND_CANCELS_ACTIVE_TASKS",
            "detachedTasks": False,
            "generationPublicationAdapterField": "generationPublicationAdapter",
            "generationPublicationAdapterType": "GenerationLocalJobPublicationAdapterV1",
            "generationJobWithoutAdapter": "REJECT_PUBLICATION_AUTHORITY_UNAVAILABLE_BEFORE_ENQUEUE",
            "completion": "EXACTLY_ONE_TERMINAL_STORE_TRANSITION_PER_CLAIMED_ATTEMPT",
            "directTerminalSuccess": "FORBIDDEN_REQUIRES_AWAITING_PUBLICATION_AND_RECEIPT",
            "publisherSuspension": "FORBIDDEN_NO_ASYNC_ACROSS_EFFECT_AND_READBACK",
            "unknownOperation": "PERMANENT_VISIBLE_FAILURE_AND_STAGING_CLEANUP",
            "progress": "CHECKPOINT_AND_SCOPED_VISIBLE_STATE",
        },
        "transitions": {
            "sameStateAllowed": True,
            "rows": transitions,
            "staleAttemptDisposition": "FAIL_CLOSED_NO_EFFECT",
            "nonTerminalStates": ["QUEUED", "RUNNING", "CANCELLATION_REQUESTED", "BLOCKED_PROTECTED_DATA", "AWAITING_PUBLICATION"],
            "terminalStates": ["SUCCEEDED", "FAILED", "CANCELLED"],
        },
        "publicationBoundaries": [
            "BEFORE_OPERATION",
            "BEFORE_CHECKPOINT",
            "AFTER_CHECKPOINT",
            "BEFORE_OUTPUT_PUBLICATION",
            "AFTER_OUTPUT_PUBLICATION",
            "BEFORE_TERMINAL_STORE_TRANSITION",
        ],
        "cancellation": {
            "structuredCancellationRequired": True,
            "checksAt": ["BEFORE_OPERATION", "BEFORE_CHECKPOINT", "AFTER_CHECKPOINT", "BEFORE_OUTPUT_PUBLICATION", "AFTER_OUTPUT_PUBLICATION"],
            "queuedRequest": "REMOVE_STAGING_THEN_MARK_CANCELLED",
            "runningRequest": "CANCEL_CHILD_REMOVE_STAGING_MARK_CANCELLED",
            "awaitingPublicationRequest": "PERSIST_PENDING_CANCELLATION_THEN_ADOPT_ONLY",
            "relaunchCancellationRequested": "MARK_CANCELLED_NO_WORKER_PUBLICATION",
            "partialOutputSHA256": "MUST_REMAIN_ABSENT",
            "stagingCleanup": "EXACT_JOB_SCOPED_RELATIVE_PATH_OR_FAIL_CLOSED",
            "cleanupFailure": "RETRYABLE_VISIBLE_FAILURE",
            "lateCompletion": "STALE_NO_EFFECT_NO_DUPLICATE_TERMINAL_TRANSITION",
        },
        "publication": {
            "intermediateState": "AWAITING_PUBLICATION",
            "pendingField": "pendingPublication",
            "receiptField": "publicationReceipt",
            "modes": PUBLICATION_MODES,
            "dispositions": PUBLICATION_DISPOSITIONS,
            "durabilityOrder": [
                "PERSIST_PENDING_PUBLICATION",
                "PUBLISH_OR_ADOPT_EFFECT_OR_EXACT_READBACK",
                "PERSIST_PUBLICATION_RECEIPT",
                "TERMINAL_SUCCEEDED",
            ],
            "outputAuthority": {
                "stagingOnlyUntilReceipt": True,
                "outputSHA256PublishedOnlyAfterReceipt": True,
                "directTerminalSuccess": False,
                "receiptBindsJobAttemptKindAndOutputSHA256": True,
            },
            "publisher": {
                "type": "ResumableLocalJobPublisherV1",
                "signature": "(ResumableLocalJobPublicationContextV1) throws -> LocalJobPublicationOutcomeV1",
                "synchronous": True,
                "idempotent": True,
                "readbackRequired": True,
                "publishOrAdoptMayCreateEffect": True,
                "publishOrAdoptAdoptsExactReadback": True,
                "adoptOnlyMayCreateEffect": False,
                "adoptOnlyAbsentOutcome": "ABSENT",
                "effectBeforeReceiptRelaunch": "ADOPT_ONLY_OR_PUBLISH_OR_ADOPT_EXACT_READBACK",
                "publisherIdempotencyKey": "JOB_ID_ATTEMPT_COUNT_KIND_OUTPUT_SHA256",
                "readbackReceipt": "PUBLICATION_RECEIPT_PERSISTED_AFTER_EFFECT_OR_ADOPTION",
            },
            "generationAuthority": {
                "mandatoryWhenGenerationEpochPresent": True,
                "authorityType": "ResumableLocalJobPublicationAuthorityV1",
                "adapterType": "GenerationLocalJobPublicationAdapterV1",
                "adapterField": "generationPublicationAdapter",
                "exactGenerationEpochArgument": "GenerationEpochV1",
                "injectedCommitFunction": "withAuthorizedCommit",
                "effectAndReadbackClosure": "SYNCHRONOUS_NO_SUSPENSION",
                "validateBeforeEffect": True,
                "validateAfterEffectBeforeReceipt": True,
                "heldAcrossAtomicEffectAndReadback": True,
                "missingAuthorityDisposition": "FAIL_CLOSED_NO_PUBLICATION",
            },
            "relaunch": {
                "awaitingPublication": "RECONCILE_DURABLE_PENDING_PUBLICATION",
                "effectBeforeReceipt": "ADOPT_EXACT_READBACK_BEFORE_TERMINAL_RECEIPT",
                "cancellationRequested": "ADOPT_ONLY; ABSENT_THEN_CLEANUP_AND_CANCEL",
                "absentWithoutCancellation": "SUPPRESS_RETRY_AND_REMAIN_AWAITING_PUBLICATION",
            },
            "retry": {
                "suppressedPublicationRetries": True,
                "automaticRetrySpin": False,
                "failedReadbackDisposition": "SUPPRESS_RETRY_UNTIL_EXPLICIT_RETRY_OR_RELAUNCH",
                "explicitRetryClearsSuppression": True,
                "relaunchClearsSuppression": True,
            },
            "destructiveRemoval": {
                "cancelActiveRowsFirst": True,
                "awaitActiveTasks": True,
                "reconcileAwaitingPublication": True,
                "requireAllRowsTerminal": True,
                "cleanupBeforeDurableRemoval": True,
                "ambiguousPublicationDisposition": "FAIL_CLOSED_RETAIN_ROW",
                "destructiveRemovalOnPublicationFailure": "FORBIDDEN",
            },
        },
        "generationLease": {
            "longReadRole": "READER",
            "acquireBeforeOperation": True,
            "validateBeforeCheckpoint": True,
            "validateBeforeTerminalPublication": True,
            "closeExactlyOnce": True,
            "publicationAuthorityRequired": True,
            "publicationAuthorityType": "ResumableLocalJobPublicationAuthorityV1",
            "publicationAuthorityHeldAcrossEffectAndReadback": True,
            "publicationAdapterType": "GenerationLocalJobPublicationAdapterV1",
            "publicationAdapterField": "generationPublicationAdapter",
            "exactGenerationEpochArgument": "GenerationEpochV1",
            "injectedCommitFunction": "withAuthorizedCommit",
            "effectAndReadbackSuspension": "FORBIDDEN",
            "lostLeaseDisposition": "GENERATION_LEASE_LOST_RETRYABLE_NO_OUTPUT_PUBLICATION",
            "missingRegistryDisposition": "GENERATION_LEASE_UNAVAILABLE_VISIBLE_FAILURE",
        },
        "failureRecovery": {
            "PROTECTED_DATA_UNAVAILABLE": "BLOCKED_PROTECTED_DATA_NO_PARTIAL_OUTPUT",
            "GENERATION_LEASE_LOST": "FAILED_RETRYABLE_NO_PARTIAL_OUTPUT",
            "RETRYABLE": "FAILED_RETRYABLE_AFTER_STAGING_CLEANUP",
            "PERMANENT": "FAILED_PERMANENT_AFTER_STAGING_CLEANUP",
            "PUBLICATION_READBACK_ABSENT": "SUPPRESS_RETRY_NO_SPIN_REMAIN_AWAITING_PUBLICATION",
            "EFFECT_BEFORE_RECEIPT": "RELAUNCH_ADOPTS_EXACT_READBACK",
            "retryUsesSameJobIdentity": True,
            "receiptDisposition": "DURABLE_STORE_STATE_AND_CANONICAL_OWNER_RECONCILE",
        },
        "backgroundAcceleration": {
            "allowed": False,
            "shortUIKitAtomicBoundaryOnly": True,
            "correctnessOwner": "FOREGROUND_LOCAL_JOB_AND_CANONICAL_OWNER",
            "expiration": "CANCEL_AND_CLEANUP",
        },
        "sourceBindings": source_bindings(),
        "excludedBehaviors": [
            "REMOTE_SYNC_OR_PROVIDER_STATE",
            "ACCOUNT_AUTHENTICATION_OR_TENANCY",
            "UNBOUNDED_MEDIA_OR_MEMORY",
            "SIGNING_DISTRIBUTION_OR_PUBLIC_METADATA",
            "PHYSICAL_THERMAL_OR_BATTERY_CLAIM_FROM_SIMULATOR",
        ],
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def lifecycle_rows() -> list[dict[str, Any]]:
    return [
        {"dimension": "MIGRATION", "required": True, "disposition": "ABSENT_OR_OLDER_VERSION_MIGRATES; UNKNOWN_OR_CORRUPT_QUARANTINES_AND_REBUILDS", "receipt": "LocalJobStoreMigrationReceiptV1"},
        {"dimension": "ARCHIVE", "required": True, "disposition": "JOB_KIND_ARCHIVE_REBUILDABLE_FROM_CANONICAL_INPUTS", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "RESTORE_VALIDATION", "required": True, "disposition": "REBUILD_ELIGIBLE_WORK_FROM_CANONICAL_INCOMPLETE_INTENTS", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "REPORT_GENERATION", "required": True, "disposition": "JOB_KIND_FINALIZE_OR_RENDER_OFF_MAIN", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "SEARCH_REBUILD", "required": True, "disposition": "JOB_KIND_SEARCH_REBUILD_FROM_NAMED_CANONICAL_INPUTS", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "IMPORT", "required": True, "disposition": "JOB_KIND_IMPORT_WITH_CHECKPOINT_AND_CANCELLATION", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "STARTER_INSTALLATION", "required": True, "disposition": "JOB_KIND_STARTER_INSTALLATION_WITH_CHECKPOINT_AND_CANCELLATION", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "MEDIA_PROCESSING", "required": True, "disposition": "JOB_KIND_MEDIA_PROCESSING_WITH_BOUNDED_PROXY", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "USER_BACKUP", "required": True, "disposition": "EXCLUDE_OPERATIONAL_CHECKPOINTS", "receipt": "NONE"},
        {"dimension": "USER_EXPORT", "required": True, "disposition": "EXCLUDE_OPERATIONAL_CHECKPOINTS", "receipt": "NONE"},
        {"dimension": "REPLACE_RESTORE", "required": True, "disposition": "DO_NOT_IMPORT_DEVICE_CHECKPOINTS_REBUILD_ELIGIBLE_WORK", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "CLONE", "required": True, "disposition": "NOT_APPLICABLE_DEVICE_LOCAL_OPERATIONAL_STATE", "receipt": "NONE"},
        {"dimension": "FORK", "required": True, "disposition": "NOT_APPLICABLE_DEVICE_LOCAL_OPERATIONAL_STATE", "receipt": "NONE"},
        {"dimension": "REPLAY", "required": True, "disposition": "RELAUNCH_RECONCILES_DURABLE_ROWS_IDEMPOTENTLY; AWAITING_PUBLICATION_ADOPTS_EXACT_READBACK", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "RELAUNCH", "required": True, "disposition": "RUNNING_REQUEUES; CANCELLATION_REQUESTED_CANCELS; AWAITING_PUBLICATION_RECONCILES", "receipt": "LOCAL_JOB_STATE"},
        {"dimension": "WORKSPACE_DELETE", "required": True, "disposition": "REMOVE_WORKSPACE_OPERATIONAL_CHECKPOINTS_CANONICAL_TRUTH_PRESERVED", "receipt": "NONE"},
        {"dimension": "ERASE", "required": True, "disposition": "REMOVE_ALL_OPERATIONAL_CHECKPOINTS_CANONICAL_ERASE_AUTHORITY_PRESERVED", "receipt": "NONE"},
        {"dimension": "EXPIRY", "required": True, "disposition": "REMOVE_EXPIRED_TERMINAL_OPERATIONAL_ROWS", "receipt": "NONE"},
        {"dimension": "RETENTION", "required": True, "disposition": "BOUNDED_BY_MAXIMUM_JOB_COUNT_AND_STORE_BYTES", "receipt": "NONE"},
        {"dimension": "DOWNGRADE", "required": True, "disposition": "DROP_AND_REBUILD_AFTER_CANONICAL_STATE_AND_IMMUTABLE_OUTPUT_SURVIVAL_PROOF", "receipt": "NONE"},
    ]


def store_contract() -> dict[str, Any]:
    return seal({
        **base("LocalJobStoreLifecycleContractV1"),
        "owner": "LocalJobStoreSchemaV1",
        "persistentContractSchema": "LOCAL_JOB_STORE_SCHEMA_V1",
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "store": {
            "kind": "DEVICE_LOCAL_OPERATIONAL_CHECKPOINT_STORE",
            "deviceLocal": True,
            "canonicalSwiftDataStore": False,
            "canonicalSchemaReleaseLease": False,
            "strictFixedSchema": True,
            "genericEntityValuePersistence": False,
            "directoryName": "local-jobs-v1",
            "storeFileName": "jobs.json",
            "migrationReceiptFileName": "migration-receipt.json",
            "quarantineDirectoryName": "quarantine",
            "currentVersion": 1,
            "maximumJobCount": 10000,
            "maximumStoreBytes": 33554432,
            "ordering": "JOB_ID_LOWERCASE_LEXICOGRAPHIC",
            "uniqueJobIdentity": True,
        },
        "migration": {
            "sourceValues": ["ABSENT", "VERSION_1", "OLDER_VERSION", "UNKNOWN_OR_CORRUPT"],
            "dispositions": ["CREATED_EMPTY", "OPENED_CURRENT", "MIGRATED", "QUARANTINED_AND_REBUILT"],
            "absentOrOlderVersionRequired": True,
            "unknownOrCorruptDisposition": "QUARANTINE_DELETE_AND_RECONSTRUCT_EMPTY",
            "receiptType": "LocalJobStoreMigrationReceiptV1",
            "receiptFields": ["schemaVersion", "source", "disposition", "sourceStoreVersion", "destinationStoreVersion", "migratedJobCount", "occurredAt"],
        },
        "durability": {
            "encoder": "SORTED_KEYS_MILLISECONDS_SINCE_1970",
            "atomicReplace": True,
            "completeFileProtection": True,
            "excludedFromUserBackup": True,
            "boundedReadBeforeDecode": True,
            "partialCanonicalStoreAuthority": False,
            "receiptAndStoreRecovery": "REBUILD_EMPTY_ON_UNKNOWN_OR_CORRUPT",
            "quarantinePermissions": "DEVICE_LOCAL_PROTECTED",
        },
        "lifecycleDimensions": lifecycle_rows(),
        "publicationLifecycle": {
            "intermediateState": "AWAITING_PUBLICATION",
            "pendingField": "pendingPublication",
            "receiptField": "publicationReceipt",
            "modes": PUBLICATION_MODES,
            "dispositions": PUBLICATION_DISPOSITIONS,
            "stateRows": [
                {"from": "RUNNING", "to": "AWAITING_PUBLICATION", "guard": "FINAL_CHECKPOINT_DURABLE_AND_RESULT_VALID"},
                {"from": "CANCELLATION_REQUESTED", "to": "AWAITING_PUBLICATION", "guard": "FINAL_CHECKPOINT_DURABLE_AND_PENDING_CANCELLATION"},
                {"from": "AWAITING_PUBLICATION", "to": "SUCCEEDED", "guard": "PUBLISHED_OR_ADOPTED_AND_RECEIPT_DURABLE"},
                {"from": "AWAITING_PUBLICATION", "to": "CANCELLED", "guard": "ADOPT_ONLY_ABSENT_AND_STAGING_CLEANUP_PROVED"},
            ],
            "publisherIdempotency": {
                "required": True,
                "key": "JOB_ID_ATTEMPT_COUNT_KIND_OUTPUT_SHA256",
                "readbackReceipt": "PUBLICATION_RECEIPT_V1",
                "effectBeforeReceiptRelaunch": "ADOPT_EXACT_READBACK",
            },
            "generationPublicationAuthority": {
                "mandatoryWhenGenerationEpochPresent": True,
                "authorityType": "ResumableLocalJobPublicationAuthorityV1",
                "heldAcrossEffectAndReadback": True,
            },
            "retrySuppression": {
                "suppressedPublicationRetries": True,
                "automaticRetrySpin": False,
                "explicitRetryOrRelaunchRequired": True,
            },
            "destructiveRemoval": {
                "cancelActiveRowsFirst": True,
                "awaitActiveTasks": True,
                "reconcileAwaitingPublication": True,
                "requireAllRowsTerminal": True,
                "cleanupBeforeDurableRemoval": True,
                "failClosedRetainRowOnAmbiguousPublication": True,
            },
        },
        "backupRestore": {
            "includedInUserBackup": False,
            "includedInUserExport": False,
            "restoreImportsCheckpoints": False,
            "restoreRebuildsFromCanonicalIncompleteIntents": True,
            "sourceCheckpointMayBecomeDestinationAuthority": False,
            "destinationStartsWithFreshLocalStore": True,
        },
        "deleteEraseExpiry": {
            "workspaceDeleteRemovesCheckpoints": True,
            "eraseRemovesCheckpoints": True,
            "expiryRemovesCheckpoints": True,
            "canonicalWorkspaceTruthPreservedUntilItsOwnerActs": True,
            "activeRowsRequireCancellationBeforeWorkspaceRemoval": True,
        },
        "relaunchReplay": {
            "enabled": True,
            "runningDisposition": "REQUEUE_RETRYABLE",
            "cancellationRequestedDisposition": "CANCELLED",
            "awaitingPublicationDisposition": "RECONCILE_PUBLISH_OR_ADOPT",
            "effectBeforeReceiptDisposition": "ADOPT_EXACT_READBACK_BEFORE_RECEIPT",
            "publicationFailureDisposition": "SUPPRESS_RETRY_NO_SPIN",
            "terminalRowsRemainUntilExplicitRemovalOrExpiry": True,
            "sameJobIdentityAfterReplay": True,
            "arrivalOrderAuthority": False,
        },
        "downgrade": {
            "disposition": "DROP_AND_REBUILD_AFTER_CANONICAL_SURVIVAL_PROOF",
            "releasedSchemaRewrite": False,
            "immutableOutputRewrite": False,
        },
        "apiClosure": [
            "enqueue", "job", "jobs", "requestCancellation", "resumePending",
            "removeTerminal", "removeJobs", "eraseAll", "removeExpired",
            "migrationReceipt", "claimForExecution", "saveCheckpoint", "markSucceeded",
            "markAwaitingPublication", "markPublicationSucceeded", "markPublicationAbsentAndCancelled",
            "markCancelled", "markFailed", "requeue",
        ],
        "sourceBindings": source_bindings()[2:5],
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


SCALE_BUDGETS = [
    {
        "fixture": "ASSET_1", "assetCount": 1, "proxyByteCount": 0,
        "maximumConcurrency": 1, "chunkByteCount": 262144,
        "maximumResidentMemoryBytes": 67108864, "p50LatencyMilliseconds": 250,
        "p95LatencyMilliseconds": 1000, "maximumInitialStallMilliseconds": 250,
        "progressHeartbeatMilliseconds": 500,
    },
    {
        "fixture": "ASSET_100", "assetCount": 100, "proxyByteCount": 0,
        "maximumConcurrency": 2, "chunkByteCount": 524288,
        "maximumResidentMemoryBytes": 134217728, "p50LatencyMilliseconds": 2000,
        "p95LatencyMilliseconds": 5000, "maximumInitialStallMilliseconds": 500,
        "progressHeartbeatMilliseconds": 1000,
    },
    {
        "fixture": "ASSET_10000", "assetCount": 10000, "proxyByteCount": 0,
        "maximumConcurrency": 2, "chunkByteCount": 524288,
        "maximumResidentMemoryBytes": 201326592, "p50LatencyMilliseconds": 15000,
        "p95LatencyMilliseconds": 30000, "maximumInitialStallMilliseconds": 1000,
        "progressHeartbeatMilliseconds": 2000,
    },
    {
        "fixture": "LARGE_MEDIA_PROXY", "assetCount": 1, "proxyByteCount": 536870912,
        "maximumConcurrency": 1, "chunkByteCount": 1048576,
        "maximumResidentMemoryBytes": 134217728, "p50LatencyMilliseconds": 10000,
        "p95LatencyMilliseconds": 25000, "maximumInitialStallMilliseconds": 1000,
        "progressHeartbeatMilliseconds": 2000,
    },
]


def budget_contract() -> dict[str, Any]:
    return seal({
        **base("ConcurrencyScaleBudgetPolicyV1"),
        "owner": "JobScaleBudgetPolicyV1",
        "policyVersion": 1,
        "maximumRunnerConcurrency": 2,
        "budgetFields": [
            "fixture", "assetCount", "proxyByteCount", "maximumConcurrency", "chunkByteCount",
            "maximumResidentMemoryBytes", "p50LatencyMilliseconds", "p95LatencyMilliseconds",
            "maximumInitialStallMilliseconds", "progressHeartbeatMilliseconds",
        ],
        "frozenBudgets": SCALE_BUDGETS,
        "measurement": {
            "minimumRepetitions": 20,
            "additionalBatchMaximum": 10,
            "additionalBatchConditionPercent": 5,
            "gateStatistic": "P95",
            "zeroHangsRequired": True,
            "maximumIsDiagnosticExceptHang": True,
            "singleSamplePass": False,
            "thresholdMutation": "FORBIDDEN",
            "measurementBinding": ["EXACT_HEAD", "EXACT_TREE", "TOOLCHAIN_RUNTIME", "FIXTURE_DIGEST", "DEVICE_CLASS", "POWER_MODE", "ACCESSIBILITY_PROFILE", "COLD_OR_WARM_STATE"],
            "requiredMeasurements": ["P50_LATENCY", "P95_LATENCY", "PEAK_RESIDENT_MEMORY", "CONCURRENCY_TRACE", "INITIAL_STALL", "PROGRESS_HEARTBEAT", "END_TO_END_ENQUEUE_TO_PUBLISHED_LATENCY", "FINAL_HEARTBEAT_GAP", "EXPLICIT_COMPLETED_JOB_IDS", "HANG_COUNT"],
        },
        "publicationMeasurements": {
            "endToEndLatency": {
                "name": "END_TO_END_ENQUEUE_TO_PUBLISHED_LATENCY",
                "start": "ENQUEUE",
                "end": "PUBLISHED_OR_ADOPTED_RECEIPT",
                "includesPublisherReadback": True,
                "requiredPerRepetition": True,
            },
            "finalHeartbeatGap": {
                "name": "FINAL_HEARTBEAT_GAP",
                "measuredThrough": "PUBLISHER_FINISH",
                "requiredPerCompletedJob": True,
            },
            "completionEvidence": {
                "completedJobIDsRequired": True,
                "hangCountRequired": True,
                "hangCountMustEqual": 0,
                "completedJobIDCountEqualsRepetitions": True,
            },
        },
        "concurrency": {
            "runnerMaximum": 2,
            "backpressure": True,
            "oneActiveTaskConsumesOneSlot": True,
            "oversubscriptionDisposition": "FAIL_CLOSED",
            "concurrentFinalizeExportDeleteArbitration": "SERIAL_CANONICAL_OWNER_WITH_BOUNDED_LOCAL_WORKERS",
        },
        "largeMediaProxy": {
            "proxyByteCount": 536870912,
            "maximumConcurrency": 1,
            "chunkByteCount": 1048576,
            "maximumResidentMemoryBytes": 134217728,
            "physicalThermalOrBatteryClaim": False,
        },
        "breachRecovery": {
            "requiredDisposition": "DISABLE_OVER_BUDGET_OPTIONAL_PATH_OR_USE_ACCEPTED_ADAPTER",
            "silentBudgetLoosening": False,
            "rerunAfterRecovery": True,
            "canonicalDataSurvival": True,
        },
        "sourceBindings": [source_bindings()[5]],
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def executable_evidence() -> list[dict[str, Any]]:
    return [
        {
            "case": "PROTECTED_DATA_FAILURE_HOOK",
            "testPath": SOURCE_PATHS[23],
            "requiredTokens": ["protectedDataFailureHook", "protectedDataUnavailable"],
        },
        {
            "case": "CORRUPT_STORE_QUARANTINE_REBUILD",
            "testPath": SOURCE_PATHS[23],
            "requiredTokens": ["corruptBytes", "quarantinedAndRebuilt", "quarantineDirectoryName"],
        },
        {
            "case": "RELAUNCH_CANCELLATION_CLEANUP",
            "testPath": SOURCE_PATHS[23],
            "requiredTokens": ["relaunch-cancel", "resumePending", "interruptedStagingURL", ".cancelled"],
        },
        {
            "case": "HOSTILE_SYMLINK_CLEANUP",
            "testPath": SOURCE_PATHS[23],
            "requiredTokens": ["createSymbolicLink", "hostile-symlink", "outsideSentinel", "symlink staging cleanup must fail closed"],
        },
        {
            "case": "DESTRUCTIVE_REMOVE_RECONCILIATION",
            "testPath": SOURCE_PATHS[23],
            "requiredTokens": ["removeJobs(workspaceID:", "eraseAll()", "awaitingRemove", "awaitingErase"],
        },
    ]


def corpus_contract() -> dict[str, Any]:
    scale_cases = [
        {"caseID": row["fixture"], "fixture": row["fixture"], "assetCount": row["assetCount"], "proxyByteCount": row["proxyByteCount"], "budgetReference": row["fixture"]}
        for row in SCALE_BUDGETS
    ]
    return seal({
        **base("ConcurrencyScaleCorpusManifestV1"),
        "fixturePath": SOURCE_PATHS[24],
        "fixtureSchema": "V21P02C05ConcurrencyScaleCorpusV1",
        "fixtureSchemaVersion": 1,
        "testPath": SOURCE_PATHS[23],
        "fixtureTopLevelFields": ["schema", "schemaVersion", "cardID", "authority", "generator", "synthetic", "containsCustomerData", "containsSecrets", "scaleCases", "hostileCases", "interruptionBoundaries", "recoveryCases", "provisional"],
        "scaleCases": scale_cases,
        "fixtureScaleCaseFields": ["caseID", "fixture", "assetCount", "proxyByteCount", "budgetReference", "expectedLogicalChunkCount", "measurementRepetitions", "proxyBacking"],
        "scaleCaseMetrics": [
            {"caseID": "ASSET_1", "expectedLogicalChunkCount": 1, "measurementRepetitions": 20},
            {"caseID": "ASSET_100", "expectedLogicalChunkCount": 1, "measurementRepetitions": 20},
            {"caseID": "ASSET_10000", "expectedLogicalChunkCount": 20, "measurementRepetitions": 20},
            {"caseID": "LARGE_MEDIA_PROXY", "expectedLogicalChunkCount": 512, "measurementRepetitions": 20, "proxyBacking": "FILE_BACKED_SPARSE"},
        ],
        "evidence": [{"evidenceID": evidence, "testMethod": method} for evidence, method in zip(EVIDENCE_IDS, TEST_METHODS)],
        "requiredCoverage": {
            "G01": ["OFF_MAIN_WORKER_EXECUTION", "DETERMINISTIC_JOB_AND_CHUNK_IDENTIFIERS", "EXACTLY_ONCE_COMPLETION", "MAIL_CALLBACK_REGRESSION"],
            "A01": ["DURABLE_BOUNDED_CHECKPOINTS", "RELAUNCH_RESUMES_FROM_CHECKPOINT", "MONOTONIC_CHECKPOINTS", "NO_STALE_ATTEMPT_EFFECT"],
            "H01": ["STRUCTURED_CANCELLATION", "STAGING_CLEANUP", "NO_PARTIAL_OUTPUT", "PROTECTED_DATA_AND_UNKNOWN_FAILURE_VISIBLE"],
            "I01": ["GENERATION_LEASE_FENCE", "STALE_PUBLICATION_REJECTED", "CONCURRENCY_BACKPRESSURE", "EXACTLY_ONCE_LEASE_CLOSE"],
            "R01": ["ASSET_1_100_10000_MATRIX", "LARGE_MEDIA_PROXY", "P50_P95_PEAK_MEMORY", "NO_SINGLE_SAMPLE_PASS", "ENQUEUE_TO_PUBLISHED_LATENCY", "FINAL_HEARTBEAT_GAP", "EXPLICIT_COMPLETED_JOB_IDS", "ZERO_HANG_COUNT"],
        },
        "executableEvidence": executable_evidence(),
        "hostileFailClosed": True,
        "customerDataPresent": False,
        "secretsPresent": False,
        "fixtureGeneratedByTooling": False,
        "exactFiveTestMethods": True,
        "lifecycle": {
            "operationalCheckpointStore": "SEPARATELY_VERSIONED_DEVICE_LOCAL",
            "userBackupAndExport": "EXCLUDED",
            "replaceRestore": "REBUILD_FROM_CANONICAL_INCOMPLETE_INTENTS",
            "workspaceDeleteEraseExpiry": "REMOVE_OPERATIONAL_ROWS",
            "downgrade": "DROP_AND_REBUILD_AFTER_CANONICAL_SURVIVAL_PROOF",
            "publication": "AWAITING_PUBLICATION_RECONCILES_PUBLISH_OR_ADOPT_BEFORE_TERMINAL_RECEIPT",
            "publicationFailure": "SUPPRESS_RETRY_NO_SPIN",
            "destructiveRemoval": "FAIL_CLOSED_UNTIL_PUBLICATION_AND_STAGING_ARE_RECONCILED",
        },
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def _strict(value: Any, digest: bool = False) -> dict[str, Any]:
    """Make an exact-key recursive Draft 2020-12 schema for a value."""
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {key: _strict(child, key == "artifactDigest") for key, child in value.items()},
        }
    if isinstance(value, list):
        if not value:
            return {"type": "array", "minItems": 0, "maxItems": 0}
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
    rows = []
    for path in MANIFEST_INPUT_PATHS:
        data = generated.get(path)
        if data is None:
            source = root / path
            if not source.is_file():
                raise ContractError(f"missing sealed manifest input: {path}")
            data = source.read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    return rows


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = _rows(root, generated)
    return seal({
        **base("V23-P02-C05-tooling-manifest"),
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
            "priorFenceOverlapCount": 42,
            "authorizedPriorFenceOverlapCount": 42,
            "unauthorizedPriorFenceOverlapCount": 0,
        },
        "persistentSchemaActivatedByTooling": False,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    job = job_contract()
    store = store_contract()
    budget = budget_contract()
    corpus = corpus_contract()
    generated = {
        JOB_SCHEMA: pretty(schema("ResumableLocalJobContractV1", job)),
        STORE_SCHEMA: pretty(schema("LocalJobStoreLifecycleContractV1", store)),
        BUDGET_SCHEMA: pretty(schema("ConcurrencyScaleBudgetPolicyV1", budget)),
        CORPUS_SCHEMA: pretty(schema("ConcurrencyScaleCorpusManifestV1", corpus)),
        JOB_DOC: pretty(job),
        STORE_DOC: pretty(store),
        BUDGET_DOC: pretty(budget),
        CORPUS_DOC: pretty(corpus),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated

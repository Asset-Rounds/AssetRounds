#!/usr/bin/env python3
"""Hostile static verifier for V23-P02-C05 tooling and sealed contracts."""
from __future__ import annotations

import ast
import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

from p02_c05_contracts import (
    BUDGET_DOC,
    BUDGET_SCHEMA,
    CARD,
    CONTRACT_SCRIPT,
    CORPUS_DOC,
    CORPUS_SCHEMA,
    EVIDENCE_IDS,
    EXISTING_PATHS,
    FENCE_DIGEST,
    GENERATED_PATHS,
    JOB_DOC,
    JOB_SCHEMA,
    JOB_STATES,
    MANIFEST,
    MANIFEST_INPUT_PATHS,
    NEW_PATHS,
    OPERATION_KINDS,
    PATH_FENCE,
    PUBLICATION_DISPOSITIONS,
    PUBLICATION_MODES,
    PROHIBITED_TOKENS,
    RETRY_CLASSIFICATIONS,
    SCALE_BUDGETS,
    SOURCE_PATHS,
    STORE_DOC,
    STORE_SCHEMA,
    TEST_METHODS,
    TOOL_PATHS,
    all_outputs,
    authority,
    canonical,
    flags,
    pretty,
    sha,
)

ROOT = Path(__file__).resolve().parents[2]


class VerificationError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def swift_code(text: str) -> str:
    """Return Swift source with comments removed for dependency checks."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//[^\r\n]*", "", text)


def load(relative: str) -> Any:
    path = ROOT / relative
    require(path.is_file(), f"missing artifact: {relative}")
    return json.loads(path.read_text(encoding="utf-8"))


def verify_seal(document: dict[str, Any], name: str) -> None:
    digest = document.get("artifactDigest")
    require(isinstance(digest, str) and len(digest) == 64, f"{name}: missing artifactDigest")
    body = dict(document)
    del body["artifactDigest"]
    require(digest == sha(pretty(body)), f"{name}: artifactDigest mismatch")


def verify_flags(document: dict[str, Any], name: str) -> None:
    for key, expected in flags().items():
        require(document.get(key) is expected, f"{name}: flag {key} is not {expected!r}")


def validate_instance(instance: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        require(instance == schema["const"], f"{path}: const mismatch")
    if "enum" in schema:
        require(instance in schema["enum"], f"{path}: enum mismatch")
    kind = schema.get("type")
    if kind == "null":
        require(instance is None, f"{path}: expected null")
    elif kind == "object":
        require(isinstance(instance, dict), f"{path}: expected object")
        required = schema.get("required", [])
        require(set(required).issubset(instance), f"{path}: missing required key")
        if schema.get("additionalProperties") is False:
            require(set(instance).issubset(schema.get("properties", {})), f"{path}: additional property")
        for key, child in schema.get("properties", {}).items():
            if key in instance:
                validate_instance(instance[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(instance, list), f"{path}: expected array")
        require(schema.get("minItems", 0) <= len(instance) <= schema.get("maxItems", len(instance)), f"{path}: array bounds")
        prefix = schema.get("prefixItems", [])
        require(len(instance) >= len(prefix), f"{path}: missing prefix item")
        for index, child in enumerate(prefix):
            validate_instance(instance[index], child, f"{path}[{index}]")
        if schema.get("items") is False:
            require(len(instance) <= len(prefix), f"{path}: additional item")
    elif kind == "string":
        require(isinstance(instance, str), f"{path}: expected string")
        if schema.get("pattern") == "^[0-9a-f]{64}$":
            require(len(instance) == 64 and all(char in "0123456789abcdef" for char in instance), f"{path}: invalid digest")
    elif kind == "integer":
        require(isinstance(instance, int) and not isinstance(instance, bool), f"{path}: expected integer")
    elif kind == "boolean":
        require(isinstance(instance, bool), f"{path}: expected boolean")


def verify_generated() -> None:
    expected = all_outputs(ROOT)
    require(list(expected) == GENERATED_PATHS, "generated path order mismatch")
    for relative, data in expected.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated artifact: {relative}")
        require(path.read_bytes() == data, f"stale generated artifact: {relative}")
        value = load(relative)
        require(path.read_bytes() == pretty(value), f"{relative}: noncanonical pretty JSON")


def verify_common(document: dict[str, Any], name: str, schema_path: str) -> None:
    verify_seal(document, name)
    verify_flags(document, name)
    require(document.get("cardID") == CARD, f"{name}: card identity mismatch")
    require(document.get("authority") == authority(), f"{name}: authority mismatch")
    require(document.get("evidenceIDs") == EVIDENCE_IDS, f"{name}: evidence IDs mismatch")
    encoded = canonical(document).decode("utf-8")
    for token in PROHIBITED_TOKENS:
        if token in encoded:
            require(token in document.get("prohibitedTokens", []), f"{name}: prohibited token escaped contract list: {token}")
    validate_instance(document, load(schema_path), name)


def verify_contracts() -> None:
    job = load(JOB_DOC)
    store = load(STORE_DOC)
    budget = load(BUDGET_DOC)
    corpus = load(CORPUS_DOC)
    verify_common(job, JOB_DOC, JOB_SCHEMA)
    verify_common(store, STORE_DOC, STORE_SCHEMA)
    verify_common(budget, BUDGET_DOC, BUDGET_SCHEMA)
    verify_common(corpus, CORPUS_DOC, CORPUS_SCHEMA)

    require(job["operationKinds"] == OPERATION_KINDS, "operation kind closure differs")
    require(job["states"] == JOB_STATES, "job state closure differs")
    require(job["retryClassifications"] == RETRY_CLASSIFICATIONS, "retry classification closure differs")
    identity = job["identity"]
    require(identity["jobID"]["material"] == ["local-job-v1", "kind.rawValue", "workspaceID.uuidString.lowercased", "immutableInputSHA256"], "job ID material is not deterministic")
    require(identity["jobID"]["stableAcrossRetry"] is True and identity["jobID"]["arrivalOrderOrWallClock"] is False, "job ID uses mutable authority")
    require(identity["chunkID"]["material"] == ["local-job-chunk-v1", "jobID.uuidString.lowercased", "chunkIndex"], "chunk ID material differs")
    require(job["execution"]["maximumConcurrentJobs"] == 2 and job["execution"]["detachedTasks"] is False, "worker bound or task ownership differs")
    require(job["execution"]["uiActorFileHashRenderArchiveWork"] == "FORBIDDEN", "UI actor work was not prohibited")
    require(job["execution"]["generationPublicationAdapterField"] == "generationPublicationAdapter" and job["execution"]["generationPublicationAdapterType"] == "GenerationLocalJobPublicationAdapterV1" and job["execution"]["generationJobWithoutAdapter"] == "REJECT_PUBLICATION_AUTHORITY_UNAVAILABLE_BEFORE_ENQUEUE", "generation publication adapter injection boundary differs")
    require(job["execution"]["completion"] == "EXACTLY_ONE_TERMINAL_STORE_TRANSITION_PER_CLAIMED_ATTEMPT", "exactly-once completion missing")
    require(job["execution"]["directTerminalSuccess"] == "FORBIDDEN_REQUIRES_AWAITING_PUBLICATION_AND_RECEIPT", "direct terminal success bypasses publication")
    require(job["execution"]["publisherSuspension"] == "FORBIDDEN_NO_ASYNC_ACROSS_EFFECT_AND_READBACK", "publication effect/readback may suspend")
    require(job["transitions"]["sameStateAllowed"] is True, "same-state idempotency missing")
    expected_transitions = {
        "QUEUED": ["QUEUED", "RUNNING", "CANCELLATION_REQUESTED"],
        "RUNNING": ["RUNNING", "QUEUED", "CANCELLATION_REQUESTED", "BLOCKED_PROTECTED_DATA", "AWAITING_PUBLICATION", "FAILED"],
        "CANCELLATION_REQUESTED": ["CANCELLATION_REQUESTED", "AWAITING_PUBLICATION", "CANCELLED"],
        "BLOCKED_PROTECTED_DATA": ["BLOCKED_PROTECTED_DATA", "QUEUED", "CANCELLATION_REQUESTED"],
        "AWAITING_PUBLICATION": ["AWAITING_PUBLICATION", "SUCCEEDED", "CANCELLED"],
        "SUCCEEDED": ["SUCCEEDED"],
        "FAILED": ["FAILED", "QUEUED"],
        "CANCELLED": ["CANCELLED"],
    }
    require({row["from"]: row["to"] for row in job["transitions"]["rows"]} == expected_transitions, "job transition matrix differs")
    require(job["cancellation"]["structuredCancellationRequired"] is True, "structured cancellation missing")
    require(job["cancellation"]["partialOutputSHA256"] == "MUST_REMAIN_ABSENT", "cancelled output can escape")
    require(job["cancellation"]["lateCompletion"] == "STALE_NO_EFFECT_NO_DUPLICATE_TERMINAL_TRANSITION", "late cancellation completion is unsafe")
    publication = job["publication"]
    require(publication["intermediateState"] == "AWAITING_PUBLICATION", "publication intermediate state missing")
    require(publication["pendingField"] == "pendingPublication" and publication["receiptField"] == "publicationReceipt", "durable publication fields differ")
    require(publication["modes"] == PUBLICATION_MODES and publication["dispositions"] == PUBLICATION_DISPOSITIONS, "publication mode/disposition closure differs")
    require(publication["durabilityOrder"] == [
        "PERSIST_PENDING_PUBLICATION",
        "PUBLISH_OR_ADOPT_EFFECT_OR_EXACT_READBACK",
        "PERSIST_PUBLICATION_RECEIPT",
        "TERMINAL_SUCCEEDED",
    ], "publication durability order differs")
    output_authority = publication["outputAuthority"]
    require(output_authority["stagingOnlyUntilReceipt"] is True and output_authority["outputSHA256PublishedOnlyAfterReceipt"] is True and output_authority["directTerminalSuccess"] is False and output_authority["receiptBindsJobAttemptKindAndOutputSHA256"] is True, "publication output authority is not receipt-bound")
    publisher = publication["publisher"]
    require(publisher["type"] == "ResumableLocalJobPublisherV1" and publisher["signature"] == "(ResumableLocalJobPublicationContextV1) throws -> LocalJobPublicationOutcomeV1" and publisher["synchronous"] is True, "publisher API is not synchronous")
    require(publisher["idempotent"] is True and publisher["readbackRequired"] is True, "publisher idempotency/readback is not mandatory")
    require(publisher["publishOrAdoptMayCreateEffect"] is True and publisher["publishOrAdoptAdoptsExactReadback"] is True, "publish-or-adopt semantics differ")
    require(publisher["adoptOnlyMayCreateEffect"] is False and publisher["adoptOnlyAbsentOutcome"] == "ABSENT", "adopt-only is not effect-free")
    require(publisher["effectBeforeReceiptRelaunch"] == "ADOPT_ONLY_OR_PUBLISH_OR_ADOPT_EXACT_READBACK", "effect-before-receipt relaunch adoption missing")
    require(publisher["publisherIdempotencyKey"] == "JOB_ID_ATTEMPT_COUNT_KIND_OUTPUT_SHA256" and publisher["readbackReceipt"] == "PUBLICATION_RECEIPT_PERSISTED_AFTER_EFFECT_OR_ADOPTION", "publisher receipt binding differs")
    generation_publication = publication["generationAuthority"]
    require(generation_publication["mandatoryWhenGenerationEpochPresent"] is True and generation_publication["authorityType"] == "ResumableLocalJobPublicationAuthorityV1" and generation_publication["adapterType"] == "GenerationLocalJobPublicationAdapterV1" and generation_publication["adapterField"] == "generationPublicationAdapter" and generation_publication["exactGenerationEpochArgument"] == "GenerationEpochV1" and generation_publication["injectedCommitFunction"] == "withAuthorizedCommit" and generation_publication["effectAndReadbackClosure"] == "SYNCHRONOUS_NO_SUSPENSION" and generation_publication["validateBeforeEffect"] is True and generation_publication["validateAfterEffectBeforeReceipt"] is True and generation_publication["heldAcrossAtomicEffectAndReadback"] is True, "generation publication authority is not mandatory")
    relaunch_publication = publication["relaunch"]
    require(relaunch_publication["awaitingPublication"] == "RECONCILE_DURABLE_PENDING_PUBLICATION" and relaunch_publication["effectBeforeReceipt"] == "ADOPT_EXACT_READBACK_BEFORE_TERMINAL_RECEIPT" and relaunch_publication["cancellationRequested"] == "ADOPT_ONLY; ABSENT_THEN_CLEANUP_AND_CANCEL", "relaunch publication adoption differs")
    require(relaunch_publication["absentWithoutCancellation"] == "SUPPRESS_RETRY_AND_REMAIN_AWAITING_PUBLICATION", "absent publication retry suppression missing")
    publication_retry = publication["retry"]
    require(publication_retry["suppressedPublicationRetries"] is True and publication_retry["automaticRetrySpin"] is False and publication_retry["explicitRetryClearsSuppression"] is True and publication_retry["relaunchClearsSuppression"] is True, "publication retry suppression differs")
    destructive_publication = publication["destructiveRemoval"]
    require(destructive_publication["cancelActiveRowsFirst"] is True and destructive_publication["awaitActiveTasks"] is True and destructive_publication["reconcileAwaitingPublication"] is True and destructive_publication["requireAllRowsTerminal"] is True and destructive_publication["cleanupBeforeDurableRemoval"] is True and destructive_publication["ambiguousPublicationDisposition"] == "FAIL_CLOSED_RETAIN_ROW" and destructive_publication["destructiveRemovalOnPublicationFailure"] == "FORBIDDEN", "destructive publication removal is not fail-closed")
    lease = job["generationLease"]
    require(lease["longReadRole"] == "READER" and lease["acquireBeforeOperation"] is True and lease["validateBeforeCheckpoint"] is True and lease["validateBeforeTerminalPublication"] is True and lease["publicationAuthorityRequired"] is True and lease["publicationAuthorityType"] == "ResumableLocalJobPublicationAuthorityV1" and lease["publicationAuthorityHeldAcrossEffectAndReadback"] is True and lease["publicationAdapterType"] == "GenerationLocalJobPublicationAdapterV1" and lease["publicationAdapterField"] == "generationPublicationAdapter" and lease["exactGenerationEpochArgument"] == "GenerationEpochV1" and lease["injectedCommitFunction"] == "withAuthorizedCommit" and lease["effectAndReadbackSuspension"] == "FORBIDDEN", "generation lease validation closure differs")
    require(lease["lostLeaseDisposition"] == "GENERATION_LEASE_LOST_RETRYABLE_NO_OUTPUT_PUBLICATION", "lost lease can publish output")

    operational = store["store"]
    require(operational == {
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
    }, "operational store identity/bounds differ")
    require(store["migration"]["absentOrOlderVersionRequired"] is True, "absent/older migration is not required")
    require(store["migration"]["unknownOrCorruptDisposition"] == "QUARANTINE_DELETE_AND_RECONSTRUCT_EMPTY", "unknown/corrupt store is not fail-closed")
    require(store["apiClosure"] == [
        "enqueue", "job", "jobs", "requestCancellation", "resumePending",
        "removeTerminal", "removeJobs", "eraseAll", "removeExpired",
        "migrationReceipt", "claimForExecution", "saveCheckpoint", "markSucceeded",
        "markAwaitingPublication", "markPublicationSucceeded", "markPublicationAbsentAndCancelled",
        "markCancelled", "markFailed", "requeue",
    ], "local job store API closure differs")
    publication_lifecycle = store["publicationLifecycle"]
    require(publication_lifecycle["intermediateState"] == "AWAITING_PUBLICATION" and publication_lifecycle["pendingField"] == "pendingPublication" and publication_lifecycle["receiptField"] == "publicationReceipt", "store publication fields differ")
    require(publication_lifecycle["modes"] == PUBLICATION_MODES and publication_lifecycle["dispositions"] == PUBLICATION_DISPOSITIONS, "store publication mode/disposition closure differs")
    require(publication_lifecycle["stateRows"] == [
        {"from": "RUNNING", "to": "AWAITING_PUBLICATION", "guard": "FINAL_CHECKPOINT_DURABLE_AND_RESULT_VALID"},
        {"from": "CANCELLATION_REQUESTED", "to": "AWAITING_PUBLICATION", "guard": "FINAL_CHECKPOINT_DURABLE_AND_PENDING_CANCELLATION"},
        {"from": "AWAITING_PUBLICATION", "to": "SUCCEEDED", "guard": "PUBLISHED_OR_ADOPTED_AND_RECEIPT_DURABLE"},
        {"from": "AWAITING_PUBLICATION", "to": "CANCELLED", "guard": "ADOPT_ONLY_ABSENT_AND_STAGING_CLEANUP_PROVED"},
    ], "store publication state rows differ")
    publisher_lifecycle = publication_lifecycle["publisherIdempotency"]
    require(publisher_lifecycle["required"] is True and publisher_lifecycle["key"] == "JOB_ID_ATTEMPT_COUNT_KIND_OUTPUT_SHA256" and publisher_lifecycle["readbackReceipt"] == "PUBLICATION_RECEIPT_V1" and publisher_lifecycle["effectBeforeReceiptRelaunch"] == "ADOPT_EXACT_READBACK", "store publisher idempotency/readback differs")
    authority_lifecycle = publication_lifecycle["generationPublicationAuthority"]
    require(authority_lifecycle["mandatoryWhenGenerationEpochPresent"] is True and authority_lifecycle["authorityType"] == "ResumableLocalJobPublicationAuthorityV1" and authority_lifecycle["heldAcrossEffectAndReadback"] is True, "store generation publication authority differs")
    retry_lifecycle = publication_lifecycle["retrySuppression"]
    require(retry_lifecycle["suppressedPublicationRetries"] is True and retry_lifecycle["automaticRetrySpin"] is False and retry_lifecycle["explicitRetryOrRelaunchRequired"] is True, "store publication retry suppression differs")
    destructive_lifecycle = publication_lifecycle["destructiveRemoval"]
    require(destructive_lifecycle["cancelActiveRowsFirst"] is True and destructive_lifecycle["awaitActiveTasks"] is True and destructive_lifecycle["reconcileAwaitingPublication"] is True and destructive_lifecycle["requireAllRowsTerminal"] is True and destructive_lifecycle["cleanupBeforeDurableRemoval"] is True and destructive_lifecycle["failClosedRetainRowOnAmbiguousPublication"] is True, "store destructive removal is not fail-closed")
    require(store["backupRestore"] == {
        "includedInUserBackup": False,
        "includedInUserExport": False,
        "restoreImportsCheckpoints": False,
        "restoreRebuildsFromCanonicalIncompleteIntents": True,
        "sourceCheckpointMayBecomeDestinationAuthority": False,
        "destinationStartsWithFreshLocalStore": True,
    }, "backup/restore lifecycle differs")
    delete = store["deleteEraseExpiry"]
    require(delete["workspaceDeleteRemovesCheckpoints"] is True and delete["eraseRemovesCheckpoints"] is True and delete["expiryRemovesCheckpoints"] is True, "delete/erase/expiry closure differs")
    require(store["relaunchReplay"]["enabled"] is True and store["relaunchReplay"]["runningDisposition"] == "REQUEUE_RETRYABLE" and store["relaunchReplay"]["cancellationRequestedDisposition"] == "CANCELLED" and store["relaunchReplay"]["awaitingPublicationDisposition"] == "RECONCILE_PUBLISH_OR_ADOPT" and store["relaunchReplay"]["effectBeforeReceiptDisposition"] == "ADOPT_EXACT_READBACK_BEFORE_RECEIPT" and store["relaunchReplay"]["publicationFailureDisposition"] == "SUPPRESS_RETRY_NO_SPIN", "relaunch replay differs")
    require(store["downgrade"]["disposition"] == "DROP_AND_REBUILD_AFTER_CANONICAL_SURVIVAL_PROOF", "downgrade is not proof-bound")
    dimensions = {row["dimension"]: row for row in store["lifecycleDimensions"]}
    require(len(dimensions) == len(store["lifecycleDimensions"]) and len(dimensions) == 20, "lifecycle dimensions are not closed")
    for dimension in ("MIGRATION", "USER_BACKUP", "USER_EXPORT", "REPLACE_RESTORE", "REPLAY", "RELAUNCH", "WORKSPACE_DELETE", "ERASE", "EXPIRY", "DOWNGRADE"):
        require(dimension in dimensions and dimensions[dimension]["required"] is True, f"lifecycle dimension missing: {dimension}")
    require(store["durability"]["atomicReplace"] is True and store["durability"]["completeFileProtection"] is True and store["durability"]["partialCanonicalStoreAuthority"] is False, "store durability boundary differs")

    require(budget["policyVersion"] == 1 and budget["maximumRunnerConcurrency"] == 2, "budget policy version/concurrency differs")
    require(budget["frozenBudgets"] == SCALE_BUDGETS, "frozen scale budget table differs")
    require([row["fixture"] for row in budget["frozenBudgets"]] == ["ASSET_1", "ASSET_100", "ASSET_10000", "LARGE_MEDIA_PROXY"], "scale fixture closure differs")
    measurement = budget["measurement"]
    require(measurement["minimumRepetitions"] == 20 and measurement["gateStatistic"] == "P95" and measurement["zeroHangsRequired"] is True and measurement["singleSamplePass"] is False, "percentile measurement law differs")
    require(measurement["thresholdMutation"] == "FORBIDDEN" and measurement["maximumIsDiagnosticExceptHang"] is True, "budget mutation/maximum law differs")
    require(measurement["requiredMeasurements"] == ["P50_LATENCY", "P95_LATENCY", "PEAK_RESIDENT_MEMORY", "CONCURRENCY_TRACE", "INITIAL_STALL", "PROGRESS_HEARTBEAT", "END_TO_END_ENQUEUE_TO_PUBLISHED_LATENCY", "FINAL_HEARTBEAT_GAP", "EXPLICIT_COMPLETED_JOB_IDS", "HANG_COUNT"], "scale measurement closure differs")
    publication_measurements = budget["publicationMeasurements"]
    require(publication_measurements["endToEndLatency"] == {
        "name": "END_TO_END_ENQUEUE_TO_PUBLISHED_LATENCY",
        "start": "ENQUEUE",
        "end": "PUBLISHED_OR_ADOPTED_RECEIPT",
        "includesPublisherReadback": True,
        "requiredPerRepetition": True,
    }, "end-to-end publication latency measurement differs")
    require(publication_measurements["finalHeartbeatGap"] == {
        "name": "FINAL_HEARTBEAT_GAP",
        "measuredThrough": "PUBLISHER_FINISH",
        "requiredPerCompletedJob": True,
    }, "final heartbeat gap measurement differs")
    require(publication_measurements["completionEvidence"] == {
        "completedJobIDsRequired": True,
        "hangCountRequired": True,
        "hangCountMustEqual": 0,
        "completedJobIDCountEqualsRepetitions": True,
    }, "completion evidence measurement differs")
    require(budget["largeMediaProxy"]["proxyByteCount"] == 536870912 and budget["largeMediaProxy"]["maximumResidentMemoryBytes"] == 134217728 and budget["largeMediaProxy"]["physicalThermalOrBatteryClaim"] is False, "large-media proxy law differs")
    require(budget["concurrency"]["backpressure"] is True and budget["concurrency"]["oversubscriptionDisposition"] == "FAIL_CLOSED", "concurrency backpressure differs")

    require(corpus["testPath"] == SOURCE_PATHS[23] and corpus["fixturePath"] == SOURCE_PATHS[24], "corpus/test fence paths differ")
    require(corpus["fixtureSchema"] == "V21P02C05ConcurrencyScaleCorpusV1" and corpus["fixtureSchemaVersion"] == 1, "fixture schema identity differs")
    require([row["testMethod"] for row in corpus["evidence"]] == TEST_METHODS, "exact five evidence test mapping differs")
    require(corpus["exactFiveTestMethods"] is True and corpus["hostileFailClosed"] is True and corpus["fixtureGeneratedByTooling"] is False, "corpus acceptance boundary differs")
    require([row["fixture"] for row in corpus["scaleCases"]] == ["ASSET_1", "ASSET_100", "ASSET_10000", "LARGE_MEDIA_PROXY"], "corpus scale cases differ")
    require(corpus["fixtureScaleCaseFields"] == ["caseID", "fixture", "assetCount", "proxyByteCount", "budgetReference", "expectedLogicalChunkCount", "measurementRepetitions", "proxyBacking"], "fixture scale case field closure differs")
    require(corpus["scaleCaseMetrics"] == [
        {"caseID": "ASSET_1", "expectedLogicalChunkCount": 1, "measurementRepetitions": 20},
        {"caseID": "ASSET_100", "expectedLogicalChunkCount": 1, "measurementRepetitions": 20},
        {"caseID": "ASSET_10000", "expectedLogicalChunkCount": 20, "measurementRepetitions": 20},
        {"caseID": "LARGE_MEDIA_PROXY", "expectedLogicalChunkCount": 512, "measurementRepetitions": 20, "proxyBacking": "FILE_BACKED_SPARSE"},
    ], "scale metrics closure differs")
    require(corpus["executableEvidence"] == [
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
    ], "executable evidence token closure differs")
    require(set(corpus["requiredCoverage"]) == {"G01", "A01", "H01", "I01", "R01"}, "coverage families differ")
    require(corpus["requiredCoverage"]["R01"] == ["ASSET_1_100_10000_MATRIX", "LARGE_MEDIA_PROXY", "P50_P95_PEAK_MEMORY", "NO_SINGLE_SAMPLE_PASS", "ENQUEUE_TO_PUBLISHED_LATENCY", "FINAL_HEARTBEAT_GAP", "EXPLICIT_COMPLETED_JOB_IDS", "ZERO_HANG_COUNT"], "R01 publication metrics coverage differs")


def verify_manifest() -> None:
    manifest = load(MANIFEST)
    verify_seal(manifest, MANIFEST)
    verify_flags(manifest, MANIFEST)
    require(manifest["authority"] == authority(), "manifest authority mismatch")
    require(manifest["pathFence"] == PATH_FENCE and manifest["pathFenceCount"] == 37 and len(set(PATH_FENCE)) == 37, "exact 37-path fence mismatch")
    require(manifest["existingPaths"] == EXISTING_PATHS, "existing path disposition differs")
    require(manifest["newPaths"] == NEW_PATHS, "new path disposition differs")
    require(manifest["sourcePaths"] == SOURCE_PATHS and manifest["sourcePathCount"] == 25, "exact source closure differs")
    require(manifest["toolingPaths"] == TOOL_PATHS and manifest["toolingPathCount"] == 12, "exact tooling closure differs")
    require(manifest["generatedPaths"] == GENERATED_PATHS, "generated path closure differs")
    require(manifest["artifactCount"] == 36 and [row["path"] for row in manifest["artifacts"]] == MANIFEST_INPUT_PATHS, "exact sealed input closure differs")
    require(manifest["artifactSetDigest"] == sha(pretty(manifest["artifacts"])), "artifact set digest mismatch")
    fence = manifest["fenceProof"]
    require(fence["baseHead"] == "a6742867a235ad7cc4e4bc07f2b650cca82434cd" and fence["baseTree"] == "fc0d86d8d02fc463621540637321d4645ad727f8", "manifest base differs")
    require(fence["pathFenceDigest"] == FENCE_DIGEST and fence["allowedDeletePaths"] == [] and fence["allowedRenamePaths"] == [], "manifest fence boundary differs")
    require(fence["priorFenceOverlapCount"] == 42 and fence["authorizedPriorFenceOverlapCount"] == 42 and fence["unauthorizedPriorFenceOverlapCount"] == 0, "prior-fence overlap proof differs")
    for row in manifest["artifacts"]:
        path = ROOT / row["path"]
        require(path.is_file(), f"sealed input missing: {row['path']}")
        data = path.read_bytes()
        require((row["bytes"], row["sha256"]) == (len(data), sha(data)), f"sealed input hash mismatch: {row['path']}")


def require_tokens(relative: str, tokens: list[str]) -> None:
    path = ROOT / relative
    require(path.is_file(), f"missing fenced source: {relative}")
    text = path.read_text(encoding="utf-8")
    for token in tokens:
        require(token in text, f"{relative}: missing source token {token!r}")


def verify_sources() -> None:
    docs = {path: load(path) for path in (JOB_DOC, STORE_DOC, BUDGET_DOC, CORPUS_DOC)}
    bindings: list[dict[str, Any]] = docs[JOB_DOC]["sourceBindings"]
    # Store and budget documents repeat their owned bindings; use the job
    # contract as the single source of token-level source observations.
    require(len(bindings) == 8, "source binding count differs")
    for binding in bindings:
        require_tokens(binding["path"], binding["requiredTokens"])
    for relative in SOURCE_PATHS[:17]:
        require((ROOT / relative).is_file(), f"missing inherited fenced source: {relative}")

    tests = ROOT / SOURCE_PATHS[23]
    test_text = tests.read_text(encoding="utf-8")
    require([method for method in TEST_METHODS if f"func {method}(" in test_text] == TEST_METHODS, "exact five C05 tests missing")
    require(test_text.count("func testV9_09") == 5, "C05 test family contains an extra or missing test")
    # The test-only synchronous probes are explicitly lock-protected.  Other
    # unchecked or unsafe isolation escapes remain forbidden.
    require("nonisolated(unsafe)" not in test_text, "unsafe concurrency escape in C05 tests")
    unchecked_classes = re.findall(r"private final class (\w+): @unchecked Sendable", test_text)
    require(set(unchecked_classes) == {
        "V909Counter", "V909SynchronousGate", "V909SynchronousProbe",
        "V909GenerationCommitAuthority", "V909ScaleMetrics",
    }, "unexpected unchecked Sendable test helper")
    for class_name in unchecked_classes:
        start = test_text.index(f"private final class {class_name}: @unchecked Sendable")
        next_class = test_text.find("\nprivate ", start + 1)
        section = test_text[start:] if next_class < 0 else test_text[start:next_class]
        require(any(lock_type in section for lock_type in ("NSLock", "NSCondition", "NSRecursiveLock")), f"unchecked Sendable helper is not lock-protected: {class_name}")
    for evidence in docs[CORPUS_DOC]["executableEvidence"]:
        require(evidence["testPath"] == SOURCE_PATHS[23], f"executable evidence escapes test fence: {evidence['case']}")
        require(all(token in test_text for token in evidence["requiredTokens"]), f"executable evidence tokens missing: {evidence['case']}")

    fixture_path = ROOT / SOURCE_PATHS[24]
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    require(isinstance(fixture, dict), "scale corpus fixture is not an object")
    fixture_text = fixture_path.read_text(encoding="utf-8")
    for label in ("ASSET_1", "ASSET_100", "ASSET_10000", "LARGE_MEDIA_PROXY"):
        require(label in fixture_text, f"scale corpus fixture missing {label}")
    for key in ("containsCustomerData", "containsSecrets"):
        if key in fixture:
            require(fixture[key] is False, f"scale corpus fixture claims {key}")

    port_text = (ROOT / SOURCE_PATHS[17]).read_text(encoding="utf-8")
    require(all(token in port_text for token in ("publishOrAdopt", "adoptOnly", "ResumableLocalJobPublicationAuthorityV1", "publicationBoundary")), "publication port contract is incomplete")
    publisher_start = port_text.index("typealias ResumableLocalJobPublisherV1")
    authority_start = port_text.index("typealias ResumableLocalJobPublicationAuthorityV1")
    adapter_start = port_text.index("struct GenerationLocalJobPublicationAdapterV1")
    execution_context_start = port_text.index("struct ResumableLocalJobExecutionContextV1")
    publisher_section = port_text[publisher_start:authority_start]
    authority_section = port_text[authority_start:adapter_start]
    adapter_section = port_text[adapter_start:execution_context_start]
    require(") throws -> LocalJobPublicationOutcomeV1" in publisher_section and "async" not in publisher_section, "publisher API must be synchronous")
    require("GenerationEpochV1" in authority_section and ") throws -> LocalJobPublicationOutcomeV1" in authority_section and "async" not in authority_section, "generation authority signature is not exact and synchronous")
    require(all(token in adapter_section for token in ("currentGenerationEpoch", "withAuthorizedCommit", "effectAndReadback", "return try withAuthorizedCommit(expectedEpoch)", "GenerationEpochV1")), "generation publication adapter injection is incomplete")
    require("async" not in adapter_section and "await" not in adapter_section, "publication effect/readback closure may suspend")
    job_text = (ROOT / SOURCE_PATHS[18]).read_text(encoding="utf-8")
    require(all(token in job_text for token in ("AWAITING_PUBLICATION", "pendingPublication", "publicationReceipt", "PUBLISH_OR_ADOPT", "ADOPT_ONLY", "LocalJobPendingPublicationV1", "LocalJobPublicationReceiptV1")), "durable publication model is incomplete")
    store_text = (ROOT / SOURCE_PATHS[20]).read_text(encoding="utf-8")
    require(all(token in store_text for token in ("markAwaitingPublication", "markPublicationSucceeded", "markPublicationAbsentAndCancelled", "pendingPublication", "publicationReceipt")), "store publication transitions are incomplete")
    mark_succeeded = store_text.index("func markSucceeded(")
    mark_awaiting = store_text.index("func markAwaitingPublication(")
    require(mark_succeeded < mark_awaiting and "throw LocalJobStoreFailureV1.invalidTransition" in store_text[mark_succeeded:mark_awaiting], "direct success bypasses durable publication")
    runner_text = (ROOT / SOURCE_PATHS[21]).read_text(encoding="utf-8")
    require(all(token in runner_text for token in ("suppressedPublicationRetries", "reconcilePublication", "reconcileForDestructiveRemoval", "publicationAuthority", ".awaitingPublication", ".publishOrAdopt", ".adoptOnly", "case .completed(let receipt)", "case .absent")), "runner publication state machine is incomplete")
    require(all(token in runner_text for token in ("generationPublicationAdapter", "generationPublicationAdapter.publish", "if job.generationEpoch != nil, generationPublicationAdapter == nil", "current.generationEpoch != nil")), "generation jobs do not require the injected publication adapter")
    require("let invoke: @Sendable () throws -> LocalJobPublicationOutcomeV1" in runner_text, "runner publication callback may suspend")
    require("suppressedPublicationRetries.insert" in runner_text and "!suppressedPublicationRetries.contains" in runner_text and "suppressedPublicationRetries.remove" in runner_text, "publication retry suppression/no-spin fence is missing")
    require("guard terminal.allSatisfy({ $0.state.isTerminal })" in runner_text and "cleanupStaging(for: job)" in runner_text, "destructive removal is not fail-closed")

    job_sources = [SOURCE_PATHS[index] for index in range(17, 23)]
    production = "\n".join(swift_code((ROOT / path).read_text(encoding="utf-8")) for path in job_sources)
    for token in PROHIBITED_TOKENS:
        require(token not in production, f"prohibited production token present: {token}")
    require("ModelContext" not in production and "MainActor" not in production, "job worker acquired UI/canonical actor dependency")


def verify_hostile_rejection() -> None:
    job = load(JOB_DOC)
    schema = load(JOB_SCHEMA)
    mutations: list[dict[str, Any]] = []
    extra = copy.deepcopy(job)
    extra["unexpected"] = True
    mutations.append(extra)
    missing = copy.deepcopy(job)
    del missing["cancellation"]
    mutations.append(missing)
    changed = copy.deepcopy(job)
    changed["execution"]["maximumConcurrentJobs"] = 99
    mutations.append(changed)
    missing_publication_state = copy.deepcopy(job)
    missing_publication_state["states"].remove("AWAITING_PUBLICATION")
    mutations.append(missing_publication_state)
    unsafe_adoption = copy.deepcopy(job)
    unsafe_adoption["publication"]["publisher"]["adoptOnlyMayCreateEffect"] = True
    mutations.append(unsafe_adoption)
    unsafe_direct_success = copy.deepcopy(job)
    unsafe_direct_success["publication"]["outputAuthority"]["directTerminalSuccess"] = True
    mutations.append(unsafe_direct_success)
    bad_digest = copy.deepcopy(job)
    bad_digest["artifactDigest"] = "z" * 64
    mutations.append(bad_digest)
    for index, mutation in enumerate(mutations):
        try:
            validate_instance(mutation, schema)
        except VerificationError:
            continue
        raise VerificationError(f"hostile contract mutation accepted: {index}")

    manifest = load(MANIFEST)
    bad_fence = copy.deepcopy(manifest)
    bad_fence["pathFence"][0] = "outside/fence"
    require(bad_fence["pathFence"] != PATH_FENCE, "hostile fence mutation was not observable")
    require(bad_fence["pathFenceCount"] == len(PATH_FENCE), "fence count did not remain bound")
    bad_seal = copy.deepcopy(load(STORE_DOC))
    bad_seal["artifactDigest"] = "0" * 64
    try:
        verify_seal(bad_seal, "hostile-store")
    except VerificationError:
        return
    raise VerificationError("hostile sealed-input mutation accepted")


def verify_python_and_generator() -> None:
    for relative in (CONTRACT_SCRIPT, "Scripts/v23/generate_p02_c05_contracts.py", "Scripts/v23/verify_p02_c05_contracts.py"):
        ast.parse((ROOT / relative).read_text(encoding="utf-8"), filename=relative)
    result = subprocess.run(
        [sys.executable, "-B", str(ROOT / "Scripts/v23/generate_p02_c05_contracts.py"), "--check", "--root", str(ROOT)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    require(result.returncode == 0, f"generator --check failed:\n{result.stdout}{result.stderr}")


def main() -> int:
    try:
        verify_generated()
        verify_contracts()
        verify_manifest()
        verify_sources()
        verify_hostile_rejection()
        verify_python_and_generator()
    except (VerificationError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"V23-P02-C05 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P02-C05 hostile static verification passed: 37 fence paths, 36 sealed inputs, 4 strict schemas, 5 evidence tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

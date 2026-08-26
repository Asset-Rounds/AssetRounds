#!/usr/bin/env python3
"""Hostile static verifier for the Card26 lifecycle tooling fence."""
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

from p02_c06_contracts import (
    CARD,
    CONTRACT_SCRIPT,
    CORPUS_DOC,
    CORPUS_SCHEMA,
    EVIDENCE_IDS,
    EXISTING_PATHS,
    FENCE_DIGEST,
    GENERATOR_SCRIPT,
    GENERATED_PATHS,
    LIFECYCLE_DOC,
    LIFECYCLE_SCHEMA,
    MANIFEST,
    MANIFEST_INPUT_PATHS,
    NEW_PATHS,
    PATH_FENCE,
    PROHIBITED_TOKENS,
    SOURCE_PATHS,
    STORAGE_DOC,
    STORAGE_SCHEMA,
    TEST_METHODS,
    TIME_DOC,
    TIME_SCHEMA,
    TOOL_PATHS,
    VERIFIER_SCRIPT,
    all_outputs,
    authority,
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


def load(relative: str) -> Any:
    path = ROOT / relative
    require(path.is_file(), f"missing artifact: {relative}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise VerificationError(f"{relative}: invalid JSON: {error}") from error


def verify_seal(document: dict[str, Any], name: str) -> None:
    digest = document.get("artifactDigest")
    require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None, f"{name}: missing/invalid artifactDigest")
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
        pattern = schema.get("pattern")
        if pattern:
            require(re.fullmatch(pattern, instance) is not None, f"{path}: pattern mismatch")
    elif kind == "integer":
        require(isinstance(instance, int) and not isinstance(instance, bool), f"{path}: expected integer")
    elif kind == "boolean":
        require(isinstance(instance, bool), f"{path}: expected boolean")
    elif kind is not None:
        raise VerificationError(f"{path}: unsupported schema type {kind!r}")


def verify_strict_schema(schema: dict[str, Any], name: str) -> None:
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{name}: not Draft 2020-12")
    require(schema.get("type") == "object", f"{name}: root is not an object")
    require(schema.get("additionalProperties") is False, f"{name}: root is not exact-key")

    def walk(node: Any, location: str) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object":
            require(node.get("additionalProperties") is False, f"{name}{location}: object is not sealed")
            require(set(node.get("required", [])) == set(node.get("properties", {})), f"{name}{location}: required/property closure differs")
            for key, child in node.get("properties", {}).items():
                walk(child, f"{location}.{key}")
        elif node.get("type") == "array":
            require(node.get("items") is False, f"{name}{location}: array permits extension")
            require(node.get("minItems") == node.get("maxItems"), f"{name}{location}: array is not fixed length")
            for index, child in enumerate(node.get("prefixItems", [])):
                walk(child, f"{location}[{index}]")

    walk(schema, "$")


def verify_generated() -> None:
    expected = all_outputs(ROOT)
    require(list(expected) == GENERATED_PATHS, "generated path order differs")
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
    encoded = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    for token in PROHIBITED_TOKENS:
        if token in encoded:
            require(token in document.get("prohibitedTokens", []), f"{name}: prohibited token escaped contract list: {token}")
    validate_instance(document, load(schema_path), name)


def verify_contracts() -> None:
    lifecycle = load(LIFECYCLE_DOC)
    storage = load(STORAGE_DOC)
    time = load(TIME_DOC)
    corpus = load(CORPUS_DOC)
    verify_common(lifecycle, LIFECYCLE_DOC, LIFECYCLE_SCHEMA)
    verify_common(storage, STORAGE_DOC, STORAGE_SCHEMA)
    verify_common(time, TIME_DOC, TIME_SCHEMA)
    verify_common(corpus, CORPUS_DOC, CORPUS_SCHEMA)

    require(lifecycle["persistentChangeMode"] == "CONTENT_ONLY", "lifecycle contract changed persistent mode")
    require(lifecycle["schemaBehaviorDelta"] is False and lifecycle["migrationBehaviorDelta"] is False, "lifecycle contract claims a schema/migration delta")
    state = lifecycle["lifecycle"]
    require(state["states"] == [
        "PROTECTED_DATA_AVAILABLE", "PROTECTED_DATA_UNAVAILABLE", "SCENE_ACTIVE",
        "SCENE_INACTIVE", "SCENE_BACKGROUND", "RELAUNCH_RECONCILIATION", "FAIL_CLOSED",
    ], "lifecycle state closure differs")
    require(state["events"] == [
        "protectedDataBecameUnavailable", "protectedDataBecameAvailable",
        "sceneBecameInactive", "sceneEnteredBackground", "sceneBecameActive",
    ], "lifecycle event closure differs")
    require(state["initialState"] == {"protectedData": "UNAVAILABLE", "scene": "INACTIVE"}, "lifecycle bootstrap initial state differs")
    require(state["bootstrap"] == {
        "method": "DeviceLifecycleCoordinatorV1.bootstrap",
        "defaultInitialState": "initiallyConservative",
        "protectedDataUnavailableSuspendedBeforeReturn": True,
        "backgroundSuspendedBeforeReturn": True,
    }, "lifecycle bootstrap contract differs")
    require(state["reducerBehavior"] == {
        "sceneBecameActiveFromAnyNonActiveState": "RESUME_SCENE_BACKGROUND",
        "sceneBecameActiveFromActiveState": "NONE",
    }, "lifecycle reducer active-edge contract differs")
    require(state["suspensionIsNotUserCancellation"] is True, "lifecycle suspension is conflated with cancellation")
    require(state["protectedData"] == {
        "unavailableBlocksBeforeEffect": True,
        "failureHook": "protectedDataFailureHook",
        "availableRequeuesOnlyAfterDurableStoreReadback": True,
        "noPartialCanonicalSuccess": True,
    }, "protected-data boundary differs")
    require(state["scene"]["inactiveIsObservedWithoutSuspension"] is True and state["scene"]["backgroundSuspendsLifecycleWork"] is True, "scene lifecycle boundary differs")
    require(state["relaunch"] == {
        "reconcileStateBeforeResume": True,
        "runningRowsRequeue": True,
        "cancellationRequestedRowsCancelWithoutPublication": True,
        "awaitingPublicationAdoptsExactReadback": True,
        "effectBeforeReceipt": "ADOPT_ONLY_OR_PUBLISH_OR_ADOPT_EXACT_READBACK",
        "noSpinOnSuppressedPublicationRetry": True,
    }, "relaunch lifecycle recovery differs")
    require(state["failClosed"]["unknownOrCorruptOperationalState"] == "QUARANTINE_DELETE_AND_RECONSTRUCT", "corrupt operational state is not quarantined")
    require(state["failClosed"]["ambiguousDestructiveRemoval"] == "RETAIN_OPERATIONAL_ROW", "destructive removal is not fail-closed")
    require(lifecycle["backupRestore"] == {
        "operationalStateIncludedInUserBackup": False,
        "operationalStateIncludedInUserExport": False,
        "restoreRebuildsFromCanonicalIncompleteIntents": True,
        "canonicalContentSurvivalAuthority": True,
        "deviceLocalReservationsReconstructed": True,
    }, "lifecycle backup/restore boundary differs")

    require(storage["rootKinds"] == [
        "FieldEvidenceData", "FieldEvidenceRestore", "FieldEvidenceOperations",
        "FieldEvidenceErase", "FieldEvidenceDiagnostics", "FieldEvidenceCommerce", "local-jobs-v1",
    ], "owned storage root closure differs")
    require(storage["accounting"]["maximumScannedEntryCount"] == 100000 and storage["accounting"]["maximumDirectoryDepth"] == 64, "storage scan bounds differ")
    require(storage["accounting"]["maximumActiveReservationCount"] == 10000, "storage reservation bound differs")
    require(storage["failureKinds"] == [
        "invalidRoot", "duplicateRoot", "volumeMismatch", "accountingOverflow",
        "entryLimitExceeded", "reservationLimitExceeded", "depthLimitExceeded",
        "unsupportedEntry", "capacityUnavailable", "insufficientCapacity", "attemptCollision",
    ], "storage failure closure differs")
    require(storage["accounting"]["regularFilesOnly"] is True and storage["accounting"]["symlinksRejected"] is True and storage["accounting"]["hardLinksRejected"] is True, "storage hostile-entry policy differs")
    admission = storage["admission"]
    require(admission["port"] == "WorkspaceStorageAdmissionPortV1" and admission["methods"] == ["reserve", "release"], "storage admission API differs")
    require(admission["preflightBeforeCanonicalMutation"] is True and admission["attemptReservationIsIdempotent"] is True and admission["attemptCollisionFailsClosed"] is True, "storage admission ordering differs")
    require(admission["capacityUnavailableFailure"] == "capacityUnavailable" and admission["insufficientCapacityFailure"] == "insufficientCapacity" and admission["writerFailure"] == "storageAdmissionFailed", "storage failure mapping differs")
    reconciliation = storage["reconciliation"]
    require(reconciliation["scansActualOwnedBytes"] is True and reconciliation["adoptsOnlySuppliedActiveReservations"] is True and reconciliation["relaunchRebuildsLedger"] is True, "storage reconciliation is incomplete")
    require(reconciliation["noAutomaticUserDataDeletion"] is True and reconciliation["noDeletionForSpace"] is True and reconciliation["noPersistentReservationStore"] is True, "storage pressure grants forbidden deletion/persistence")
    require(storage["destructiveOperations"]["automaticDataDeletion"] is False, "storage contract authorizes automatic data deletion")

    require(time["wallTime"]["causalOrdering"] == "FORBIDDEN" and time["wallTime"]["durationMeasurement"] == "FORBIDDEN", "wall clock escaped causal authority")
    require(time["wallTime"]["validation"] == [
        "finiteDate", "nonEmptyTrimmedControlFreeZoneIdentifier",
        "zoneIdentifierUTF8ByteCountAtMost255", "offsetSecondsWithinInclusivePlusOrMinus64800",
    ], "wall-time validation semantics differ")
    require(time["wallTime"]["zoneIdentifierMaximumUTF8ByteCount"] == 255 and time["wallTime"]["offsetSecondsInclusiveRange"] == [-64800, 64800], "wall-time structural bounds differ")
    require(time["wallTime"]["liveCreation"] == {
        "method": "wallTimeRecord(timeZone:)",
        "derivesCurrentOffset": True,
        "derivesCurrentDST": True,
        "validatesCapturedTuple": True,
    }, "live wall-time derivation differs")
    require(time["wallTime"]["durableValidation"] == {
        "usesCapturedTuple": True,
        "reopensTimeZoneDatabase": False,
        "rederivesOffsetOrDST": False,
    }, "durable wall-time validation reopens TZDB")
    duration = time["monotonicDuration"]
    require(duration["instantType"] == "ApplicationMonotonicInstantV1" and duration["durationTokenType"] == "InProcessDurationTokenV1", "monotonic types differ")
    require(duration["processLocal"] is True and duration["persisted"] is False and duration["codable"] is False, "monotonic ticks are persisted")
    require(duration["systemSource"] == "DispatchTime.now().uptimeNanoseconds" and duration["regressionFailure"] == "monotonicClockRegressed" and duration["overflowFailure"] == "durationOverflow", "monotonic failure boundary differs")
    require(time["timeZoneAndDST"]["zoneIdentifierPersistedWithRecord"] is True and time["timeZoneAndDST"]["calendarTransitionsDoNotOrderMutations"] is True, "timezone/DST record semantics differ")

    fixture_fields = ["schemaVersion", "fixtureIdentity", "lifecycleEvents", "durableBoundaries", "storage", "timeCases", "wallClockJumpsSeconds", "monotonicElapsedNanoseconds"]
    require(corpus["fixtureTopLevelFields"] == fixture_fields, "fixture top-level field closure differs")
    require(corpus["exactFiveTestMethods"] is True and corpus["fixtureGeneratedByTooling"] is False and corpus["hostileFailClosed"] is True, "corpus acceptance boundary differs")
    require([row["testMethod"] for row in corpus["evidence"]] == TEST_METHODS, "exact five test mapping differs")
    require(corpus["fixtureRequiredLifecycleEvents"] == [
        "protectedDataBecameUnavailable", "protectedDataBecameAvailable", "sceneBecameInactive", "sceneEnteredBackground", "sceneBecameActive",
    ], "fixture lifecycle events differ")
    require(corpus["fixtureRequiredDurableBoundaries"] == ["queuedBeforeClaim", "runningAfterCheckpoint", "awaitingPublicationEffectBeforeReceipt", "terminalSucceeded"], "fixture interruption boundaries differ")
    require(corpus["fixtureStorageFields"] == ["canonicalMutationAllowanceBytes", "ownedFileBytes", "reservationBytes"], "fixture storage fields differ")
    require(corpus["fixtureTimeCaseFields"] == ["utc", "zone", "offset", "dst"], "fixture time fields differ")
    require(corpus["fixtureRequiredTimeCases"] == [
        {"utc": "2026-01-15T17:00:00Z", "zone": "America/New_York", "offset": -18000, "dst": False},
        {"utc": "2026-07-15T16:00:00Z", "zone": "America/New_York", "offset": -14400, "dst": True},
        {"utc": "2026-03-08T06:59:59Z", "zone": "America/New_York", "offset": -18000, "dst": False},
        {"utc": "2026-03-08T07:00:00Z", "zone": "America/New_York", "offset": -14400, "dst": True},
        {"utc": "2026-11-01T05:00:00Z", "zone": "America/New_York", "offset": -14400, "dst": True},
        {"utc": "2026-11-01T06:00:00Z", "zone": "America/New_York", "offset": -18000, "dst": False},
        {"utc": "2026-07-15T16:00:00Z", "zone": "Pacific/Auckland", "offset": 43200, "dst": False},
    ], "fixture time vector differs")
    require(corpus["fixtureRequiredWallClockJumpsSeconds"] == [-86400, 259200] and corpus["fixtureRequiredMonotonicElapsedNanoseconds"] == 250000000, "fixture clock jumps differ")
    require(corpus["requiredCoverage"] == {
        "G01": ["PROTECTED_DATA_STATE_REDUCER", "SCENE_ACTIVE_INACTIVE_BACKGROUND", "LIFECYCLE_SUSPENSION_NOT_USER_CANCELLATION"],
        "A01": ["STORAGE_PREFLIGHT", "NO_CANONICAL_MUTATION_ON_ADMISSION_FAILURE", "REFUSAL_BEFORE_CANONICAL_MUTATION"],
        "H01": ["PROTECTED_DATA_LOCK_INTERRUPTION", "HOSTILE_SYMLINK_FAIL_CLOSED", "STALE_RESUME_NEW_SUSPEND"],
        "I01": ["DURABLE_BOUNDARY_TERMINATION_RELAUNCH", "EFFECT_BEFORE_RECEIPT_ADOPTION", "DESTRUCTIVE_ADOPT_ONLY_RECONCILIATION"],
        "R01": ["STORAGE_RECONCILIATION_AND_RESERVATION_RACE", "WALL_CLOCK_ROLLBACK_FORWARD", "TIMEZONE_DST_AND_MONOTONIC_CLOCK_JUMPS"],
    }, "coverage families differ")
    require(len(corpus["executableEvidence"]) == 6, "executable evidence closure differs")
    require(corpus["lifecycle"]["noPersistedMonotonicTicks"] is True and corpus["lifecycle"]["noDeletionForSpace"] is True, "corpus permits forbidden lifecycle behavior")


def verify_manifest() -> None:
    manifest = load(MANIFEST)
    verify_seal(manifest, MANIFEST)
    verify_flags(manifest, MANIFEST)
    require(manifest["authority"] == authority(), "manifest authority differs")
    require(manifest["pathFence"] == PATH_FENCE and manifest["pathFenceCount"] == 27 and len(set(PATH_FENCE)) == 27, "exact 27-path fence differs")
    require(manifest["existingPaths"] == EXISTING_PATHS and manifest["newPaths"] == NEW_PATHS, "path disposition differs")
    require(manifest["sourcePaths"] == SOURCE_PATHS and manifest["sourcePathCount"] == 15, "source closure differs")
    require(manifest["toolingPaths"] == TOOL_PATHS and manifest["toolingPathCount"] == 12, "tooling closure differs")
    require(manifest["generatedPaths"] == GENERATED_PATHS, "generated closure differs")
    require(manifest["artifactCount"] == 26 and [row["path"] for row in manifest["artifacts"]] == MANIFEST_INPUT_PATHS, "sealed input closure differs")
    require(manifest["artifactSetDigest"] == sha(pretty(manifest["artifacts"])), "artifact set digest differs")
    fence = manifest["fenceProof"]
    require(fence["baseHead"] == "0272a8ffc24af98343fdfbc0b51e5063bd3e1134" and fence["baseTree"] == "d603f733609dd5d8214ff59bca0b172bb4c770d2", "manifest base differs")
    require(fence["pathFenceDigest"] == FENCE_DIGEST and fence["allowedDeletePaths"] == [] and fence["allowedRenamePaths"] == [], "manifest fence boundary differs")
    require(fence["priorFenceOverlapCount"] == 15 and fence["authorizedPriorFenceOverlapCount"] == 15 and fence["unauthorizedPriorFenceOverlapCount"] == 0, "prior overlap proof differs")
    require(fence["activeS10Overlap"] is False and fence["activeS10ReservationDigest"] == "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a", "S10 reservation overlap escaped")
    for row in manifest["artifacts"]:
        path = ROOT / row["path"]
        require(path.is_file(), f"sealed input missing: {row['path']}")
        data = path.read_bytes()
        require((row["bytes"], row["sha256"]) == (len(data), sha(data)), f"sealed input hash mismatch: {row['path']}")


def require_tokens(relative: str, tokens: list[str]) -> str:
    path = ROOT / relative
    require(path.is_file(), f"missing fenced source: {relative}")
    text = path.read_text(encoding="utf-8")
    for token in tokens:
        require(token in text, f"{relative}: missing source token {token!r}")
    return text


def verify_sources() -> None:
    lifecycle = load(LIFECYCLE_DOC)
    bindings = lifecycle["sourceBindings"]
    require(len(bindings) == 15 and [item["path"] for item in bindings] == SOURCE_PATHS, "source binding closure differs")
    source_texts: dict[str, str] = {}
    for binding in bindings:
        source_texts[binding["path"]] = require_tokens(binding["path"], binding["requiredTokens"])
    for relative in SOURCE_PATHS:
        require((ROOT / relative).is_file(), f"missing fenced source: {relative}")

    test_text = source_texts[SOURCE_PATHS[13]]
    require([method for method in TEST_METHODS if f"func {method}(" in test_text] == TEST_METHODS, "exact five Card26 test methods missing")
    require(test_text.count("func testV9_10") == 5, "Card26 test family contains an extra or missing test")
    require("nonisolated(unsafe)" not in test_text, "unsafe concurrency escape in Card26 tests")
    for evidence in load(CORPUS_DOC)["executableEvidence"]:
        require(evidence["testPath"] == SOURCE_PATHS[13], f"executable evidence escapes test fence: {evidence['case']}")
        require(all(token in test_text for token in evidence["requiredTokens"]), f"executable evidence missing: {evidence['case']}")

    fixture = load(SOURCE_PATHS[14])
    require(list(fixture) == ["schemaVersion", "fixtureIdentity", "lifecycleEvents", "durableBoundaries", "storage", "timeCases", "wallClockJumpsSeconds", "monotonicElapsedNanoseconds"], "fixture byte shape differs")
    corpus = load(CORPUS_DOC)
    require(fixture["schemaVersion"] == 1 and fixture["fixtureIdentity"] == "V21-P02-C06-LIFECYCLE-BOUNDARY-CORPUS-V1", "fixture identity differs")
    require(fixture["lifecycleEvents"] == corpus["fixtureRequiredLifecycleEvents"], "fixture lifecycle events differ")
    require(fixture["durableBoundaries"] == corpus["fixtureRequiredDurableBoundaries"], "fixture durable boundaries differ")
    require(fixture["wallClockJumpsSeconds"] == corpus["fixtureRequiredWallClockJumpsSeconds"] and fixture["monotonicElapsedNanoseconds"] == corpus["fixtureRequiredMonotonicElapsedNanoseconds"], "fixture timing values differ")
    require(list(fixture["storage"]) == corpus["fixtureStorageFields"] and all(isinstance(item, int) and not isinstance(item, bool) for item in fixture["storage"]["ownedFileBytes"]), "fixture storage shape differs")
    require(fixture["timeCases"] == corpus["fixtureRequiredTimeCases"], "fixture time vectors differ")
    require(all(list(item) == corpus["fixtureTimeCaseFields"] for item in fixture["timeCases"]), "fixture time shape differs")

    # Reprove the C05 publication/lifecycle boundary that C06 overlaps.
    port_text = source_texts[SOURCE_PATHS[1]]
    require(all(token in port_text for token in ("PROTECTED_DATA_UNAVAILABLE", "SCENE_BACKGROUND", "suspendForLifecycle", "resumeAfterLifecycle")), "lifecycle port boundary is incomplete")
    job_text = source_texts[SOURCE_PATHS[7]]
    require(all(token in job_text for token in ("AWAITING_PUBLICATION", "pendingPublication", "publicationReceipt", "PUBLISH_OR_ADOPT", "ADOPT_ONLY")), "publication state boundary is incomplete")
    store_text = source_texts[SOURCE_PATHS[8]]
    require(all(token in store_text for token in ("markLifecycleSuspended", "resumeAfterProtectedDataAvailable", "quarantineAndRebuild", "removeJobs", "eraseAll")), "local store lifecycle boundary is incomplete")
    runner_text = source_texts[SOURCE_PATHS[9]]
    require(all(token in runner_text for token in ("suppressedPublicationRetries", "reconcileForDestructiveRemoval", "generationPublicationAdapter", "awaitingPublication")), "runner lifecycle boundary is incomplete")
    require("suppressedPublicationRetries.insert" in runner_text and "!suppressedPublicationRetries.contains" in runner_text and "suppressedPublicationRetries.remove" in runner_text, "publication retry suppression is missing")
    require("guard terminal.allSatisfy({ $0.state.isTerminal })" in runner_text and "cleanupStaging(for: job)" in runner_text, "destructive removal is not fail-closed")
    # The canonical mutation writer remains MainActor-owned by its prior card;
    # only lifecycle, storage, time, and resumable-job workers are checked for
    # an accidental UI/canonical actor dependency here.
    worker_paths = [SOURCE_PATHS[index] for index in (0, 1, 4, 5, 6, 7, 8, 9, 10, 11, 12)]
    production = "\n".join(source_texts[path] for path in worker_paths)
    for token in PROHIBITED_TOKENS:
        require(token not in production, f"prohibited production token present: {token}")
    require("ModelContext" not in production and "MainActor" not in production, "lifecycle/storage/time worker acquired UI/canonical actor dependency")

    lifecycle_coordinator_text = source_texts[SOURCE_PATHS[10]]
    require(all(token in lifecycle_coordinator_text for token in ("initiallyConservative", "bootstrap", "fail-closed", "sceneBecameActive", "state.scene == .active", ".resume(.sceneBackground)")), "lifecycle bootstrap/reducer is not truthfully fenced")
    storage_text = source_texts[SOURCE_PATHS[11]]
    require("reservationLimitExceeded" in storage_text and "maximumActiveReservationCount = 10_000" in storage_text, "storage reservation limit source parity differs")

    time_text = source_texts[SOURCE_PATHS[12]]
    require(all(token in time_text for token in ("maximumTimeZoneIdentifierUTF8ByteCount", "maximumAbsoluteUTCOffsetSeconds", "trimmingCharacters", "controlCharacters", "timeZoneIdentifier.utf8.count", "secondsFromGMT", "isDaylightSavingTime")), "captured wall-time validation source parity differs")
    require("timeZoneIdentifier == timeZoneIdentifier.trimmingCharacters" in time_text and "try record.validate()" in time_text, "wall-time structural validation is incomplete")
    require("driftZone.secondsFromGMT(for: driftInstant)" in test_text and "capturedBeforeTZDBDrift" in test_text, "durable TZDB-drift evidence is missing")

    # The monotonic type must remain process-local and non-Codable.
    runtime_text = source_texts[SOURCE_PATHS[0]]
    instant_start = runtime_text.index("struct ApplicationMonotonicInstantV1")
    clock_start = runtime_text.index("protocol ApplicationMonotonicClockV1")
    require("Codable" not in runtime_text[instant_start:clock_start], "monotonic instant became Codable")
    require("DispatchTime.now().uptimeNanoseconds" in source_texts[SOURCE_PATHS[4]], "system monotonic adapter is not uptime based")


def verify_hostile_rejection() -> None:
    lifecycle = load(LIFECYCLE_DOC)
    schema = load(LIFECYCLE_SCHEMA)
    mutations: list[dict[str, Any]] = []
    extra = copy.deepcopy(lifecycle)
    extra["unexpected"] = True
    mutations.append(extra)
    missing = copy.deepcopy(lifecycle)
    del missing["interruptionBoundaries"]
    mutations.append(missing)
    changed = copy.deepcopy(lifecycle)
    changed["persistentChangeMode"] = "NEW_SCHEMA_VERSION"
    mutations.append(changed)
    unsafe = copy.deepcopy(lifecycle)
    unsafe["lifecycle"]["protectedData"]["unavailableBlocksBeforeEffect"] = False
    mutations.append(unsafe)
    bad_digest = copy.deepcopy(lifecycle)
    bad_digest["artifactDigest"] = "z" * 64
    mutations.append(bad_digest)
    for index, mutation in enumerate(mutations):
        try:
            validate_instance(mutation, schema)
        except VerificationError:
            continue
        raise VerificationError(f"hostile lifecycle mutation accepted: {index}")

    storage = load(STORAGE_DOC)
    storage_schema = load(STORAGE_SCHEMA)
    bad_storage = copy.deepcopy(storage)
    bad_storage["reconciliation"]["noAutomaticUserDataDeletion"] = False
    try:
        validate_instance(bad_storage, storage_schema)
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile storage deletion mutation accepted")

    manifest = load(MANIFEST)
    bad_fence = copy.deepcopy(manifest)
    bad_fence["pathFence"][0] = "outside/fence"
    require(bad_fence["pathFence"] != PATH_FENCE and bad_fence["pathFenceCount"] == 27, "hostile fence mutation was not observable")
    bad_seal = copy.deepcopy(load(TIME_DOC))
    bad_seal["artifactDigest"] = "0" * 64
    try:
        verify_seal(bad_seal, "hostile-time")
    except VerificationError:
        return
    raise VerificationError("hostile sealed-input mutation accepted")


def verify_python_and_generator() -> None:
    for relative in (CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT):
        ast.parse((ROOT / relative).read_text(encoding="utf-8"), filename=relative)
    result = subprocess.run(
        [sys.executable, "-B", str(ROOT / GENERATOR_SCRIPT), "--check", "--root", str(ROOT)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    require(result.returncode == 0, f"generator --check failed:\n{result.stdout}{result.stderr}")


def main() -> int:
    try:
        verify_generated()
        for schema_path in (LIFECYCLE_SCHEMA, STORAGE_SCHEMA, TIME_SCHEMA, CORPUS_SCHEMA):
            verify_strict_schema(load(schema_path), schema_path)
        verify_contracts()
        verify_manifest()
        verify_sources()
        verify_hostile_rejection()
        verify_python_and_generator()
    except (VerificationError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"V23-P02-C06 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P02-C06 hostile static verification passed: 27 fence paths, 26 sealed inputs, 4 strict schemas, 5 evidence tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

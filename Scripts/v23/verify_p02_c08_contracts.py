#!/usr/bin/env python3
"""Hostile static verifier for the Card 28 diagnostics/support tooling fence."""
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

from p02_c08_contracts import (
    APP_BASE_HEAD,
    APP_BASE_TREE,
    CARD,
    CONTRACT_SCRIPT,
    CORPUS_DOC,
    EVIDENCE_IDS,
    EXISTING_PATHS,
    FAILURE_CODES,
    FENCE_CORRECTION_RECEIPT_DIGEST,
    FENCE_DIGEST,
    GENERATED_PATHS,
    GENERATOR_SCRIPT,
    HEALTH_STATES,
    LIFECYCLE_DOC,
    MANIFEST,
    MANIFEST_INPUT_PATHS,
    NEW_PATHS,
    NEW_SOURCE_PATHS,
    OPERATIONAL_FAILURE_SCHEMA,
    PATH_FENCE,
    PROHIBITED_TOKENS,
    PRIOR_CONTEXT_DIGEST,
    PRIOR_FENCE_DIGEST,
    SCRATCH_BOUNDS,
    SCRATCH_PURPOSES,
    S2_DIAGNOSTICS_TEST_METHODS,
    SIGNPOST_INTERVALS,
    SOURCE_PATHS,
    SUPPORT_ALLOWLIST,
    SUPPORT_EXPORT_DOC,
    SUPPORT_EXPORT_SCHEMA,
    SYSTEM_HEALTH_DOC,
    SYSTEM_HEALTH_SCHEMA,
    TRANSITION_DIGEST,
    TYPED_ERROR_MAPPING,
    TYPED_ERROR_MAPPING_POLICY,
    TEST_METHODS,
    TOOL_PATHS,
    VERIFIER_SCRIPT,
    WORKFLOW_FRICTION_SCHEMA,
    all_outputs,
    authority,
    corpus_contract,
    flags,
    lifecycle_contract,
    pretty,
    sha,
    support_export_contract,
    system_health_contract,
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
    require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
            f"{name}: missing/invalid artifactDigest")
    body = dict(document)
    del body["artifactDigest"]
    require(digest == sha(pretty(body)), f"{name}: artifactDigest mismatch")


def verify_flags(document: dict[str, Any], name: str) -> None:
    for key, expected in flags().items():
        require(document.get(key) is expected, f"{name}: flag {key} is not {expected!r}")


def validate_instance(instance: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        expected = schema["const"]
        require(type(instance) is type(expected) and instance == expected, f"{path}: const mismatch")
    if "enum" in schema:
        require(instance in schema["enum"], f"{path}: enum mismatch")
    if "anyOf" in schema:
        errors = []
        for candidate in schema["anyOf"]:
            try:
                validate_instance(instance, candidate, path)
                return
            except VerificationError as error:
                errors.append(str(error))
        raise VerificationError(f"{path}: anyOf mismatch: {errors}")
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
        require(schema.get("minItems", 0) <= len(instance) <= schema.get("maxItems", len(instance)),
                f"{path}: array bounds")
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


def verify_strict_schema(document: dict[str, Any], name: str) -> None:
    require(document.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
            f"{name}: not Draft 2020-12")
    require(document.get("type") == "object", f"{name}: root is not an object")
    require(document.get("additionalProperties") is False, f"{name}: root is not exact-key")

    def walk(node: Any, location: str) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object":
            require(node.get("additionalProperties") is False, f"{name}{location}: object is not sealed")
            require(set(node.get("required", [])) == set(node.get("properties", {})),
                    f"{name}{location}: required/property closure differs")
            for key, child in node.get("properties", {}).items():
                walk(child, f"{location}.{key}")
        elif node.get("type") == "array":
            require(node.get("items") is False, f"{name}{location}: array permits extension")
            require(node.get("minItems") == node.get("maxItems"),
                    f"{name}{location}: array is not fixed length")
            for index, child in enumerate(node.get("prefixItems", [])):
                walk(child, f"{location}[{index}]")

    walk(document, "$")


def verify_generated() -> None:
    expected = all_outputs(ROOT)
    require(list(expected) == GENERATED_PATHS, "generated path order differs")
    for relative, data in expected.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated artifact: {relative}")
        require(path.read_bytes() == data, f"stale generated artifact: {relative}")
        require(path.read_bytes() == pretty(load(relative)), f"{relative}: noncanonical pretty JSON")


def verify_common(document: dict[str, Any], name: str, schema_path: str) -> None:
    verify_seal(document, name)
    verify_flags(document, name)
    require(document.get("cardID") == CARD, f"{name}: card identity mismatch")
    require(document.get("authority") == authority(), f"{name}: authority mismatch")
    require(document.get("evidenceIDs") == EVIDENCE_IDS, f"{name}: evidence IDs mismatch")
    validate_instance(document, load(schema_path), name)


def verify_health(document: dict[str, Any]) -> None:
    verify_common(document, "system-health", SYSTEM_HEALTH_SCHEMA)
    require(document["persistentChangeMode"] == "NEW_SCHEMA_VERSION", "health schema mode differs")
    health = document["health"]
    require(health["states"] == HEALTH_STATES and health["maximumFailureCount"] == 64,
            "health bounds differ")
    require(health["boundedLocalSummary"] is True and health["customerOrWorkPayload"] is False,
            "health payload boundary differs")
    registry = document["operationalFailure"]["registry"]
    require(registry["codes"] == FAILURE_CODES, "failure code closure differs")
    require(registry["exactlyOneDescriptorPerCode"] is True, "failure descriptors are not closed")
    require(document["typedErrorMapping"] == TYPED_ERROR_MAPPING
            and document["operationalFailure"]["typedErrorMapping"] == TYPED_ERROR_MAPPING,
            "typed operational failure mapping differs")
    require(document["typedErrorMappingPolicy"] == TYPED_ERROR_MAPPING_POLICY
            and document["operationalFailure"]["typedErrorMappingPolicy"]
                == TYPED_ERROR_MAPPING_POLICY,
            "typed failure mapper policy differs")
    mapping = document["typedErrorMapping"]
    require(mapping["provisionalKernelOnly"] is True
            and mapping["shippingBoundaryAdoption"]
                == "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION"
            and mapping["underlyingFailureCanBecomeEmptySuccess"] is False
            and mapping["storeWriteFailurePropagates"] is True
            and len(mapping["cases"]) == 7,
            "typed failure mapping boundary closure differs")
    require([case["boundary"] for case in mapping["cases"][:6]] == [
        "PERSISTENCE", "CONTENT", "REPORT", "BACKUP",
        "PERMISSION_FILE_AUTHORITY", "COMMERCE",
    ] and mapping["cases"][6]["expectedCode"] == "UNKNOWN",
            "typed failure mapping domains differ")
    metric = document["metricSource"]
    require(metric["activeSourceCount"] == 1, "MetricKit source is not singular")
    require(metric["ios18Source"] == "MXMetricManager", "iOS18 source changed")
    require(metric["ios18FallbackRetained"] is True and metric["betaMetricManagerAdopted"] is False,
            "MetricKit compatibility boundary differs")
    require(metric["sourceContractType"] == "MetricReportingSourceContractV1"
            and metric["sourceCount"] == 1
            and metric["retainedSource"] == "IOS18_METRICKIT_FALLBACK"
            and metric["permitsBetaOnlyAPI"] is False
            and metric["permitsSecondReportingSource"] is False,
            "MetricKit source contract differs")
    require(metric["registration"] == {
        "serialized": True,
        "desiredStateConverges": True,
        "externalCallsOutsideLock": True,
        "reentrantCallbacksSafe": True,
        "duplicateStartIsIdempotent": True,
        "duplicateStopIsIdempotent": True,
        "soleSource": "MetricKitReportingSourceV1",
    }, "MetricKit registration convergence differs")
    require(document["logging"]["signpostIntervals"] == SIGNPOST_INTERVALS
            and document["logging"]["signpostCount"] == 15,
            "signpost registry closure differs")
    friction = document["workflowFriction"]
    require(friction["declarationOnly"] is True and friction["defaultEnabled"] is False,
            "workflow friction default differs")
    require(friction["productionWriteCount"] == 0 and friction["networkRequestCount"] == 0,
            "workflow friction writes/network are enabled")
    require(document["injectedClock"]["required"] is True, "clock injection missing")
    privacy = document["privacy"]
    require(privacy["allowlistOnly"] is True and privacy["noNetwork"] is True
            and privacy["noCustomerContent"] is True and privacy["noRawLogs"] is True,
            "privacy boundary differs")


def verify_lifecycle(document: dict[str, Any]) -> None:
    verify_common(document, "lifecycle", OPERATIONAL_FAILURE_SCHEMA)
    store = document["store"]
    require(store["schemaVersion"] == 2, "support store schema is not v2")
    require(store["cloudKitDatabase"] == "NONE" and store["backupExcluded"] is True,
            "support store portability differs")
    require(store["fileProtection"] == "COMPLETE", "support store protection differs")
    require(store["protectionPolicy"] == "COMPLETE",
            "support store protection policy differs")
    require(store["accounting"] == {
        "maximumActiveReservationCount": 10_000,
        "exactCapAdmissionIsIdempotent": True,
        "invalidMetadataDoesNotMutate": True,
        "recoveryErrorsNormalizeToTypedFailure": True,
    }, "support store accounting/recovery policy differs")
    require(store["canonicalWorkspaceOpenAllowed"] is False
            and store["canonicalWorkspaceWriteAllowed"] is False,
            "support store crosses canonical boundary")
    require(store["bounds"] == {
        "maximumRecordBytes": 16_384,
        "maximumTotalBytes": 524_288,
        "maximumRecords": 128,
    }, "support store bounds differ")
    require(store["migration"]["absent"] == "CREATE_V2"
            and store["migration"]["corrupt"] == "QUARANTINE_AND_RECREATE",
            "support store migration differs")
    scratch = document["scratch"]
    require(scratch["purposes"] == SCRATCH_PURPOSES and scratch["bounds"] == SCRATCH_BOUNDS,
            "scratch bounds/purposes differ")
    require(scratch["protection"] == "COMPLETE", "scratch protection differs")
    require(scratch["purposeIsolation"] is True and scratch["terminalDeletion"]
            == ["CANCELLED", "COMPLETED", "FAILED", "EXPIRED"], "scratch lifecycle differs")
    require(scratch["recovery"] == {
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
    }, "scratch recovery/tombstone policy differs")
    export = document["exportLifecycle"]
    require(export["allowlist"] == SUPPORT_ALLOWLIST
            and export["maximumCanonicalBytes"] == 524_288
            and export["automaticUpload"] is False, "support export policy differs")
    require(document["eraseReset"]["canonicalWorkspaceMutationCount"] == 0,
            "reset/erase touches canonical workspace")
    require(document["lifecycleExclusions"]["phase10PollingDuringParallelExecution"] is False,
            "Phase 10 polling is claimed")


def verify_export(document: dict[str, Any]) -> None:
    verify_common(document, "support-export", WORKFLOW_FRICTION_SCHEMA)
    bundle = document["bundle"]
    require(bundle["allowlist"] == SUPPORT_ALLOWLIST
            and bundle["maximumCanonicalBytes"] == 524_288, "bundle allowlist/bound differs")
    require(bundle["containsCustomerContent"] is False
            and bundle["containsCustomerIdentifier"] is False
            and bundle["containsRawLogs"] is False
            and bundle["permitsAutomaticUpload"] is False, "bundle privacy differs")
    require(document["terminalReplay"] == {
        "stateMachine": ["AVAILABLE", "IN_PROGRESS", "RETRYABLE", "FINISHED"],
        "beginRequiresPrepared": True,
        "sameDispositionRetryAfterCleanupFailure": True,
        "changedDispositionRejected": True,
        "concurrentClaimRejected": True,
        "finishedClaimRejected": True,
        "receiptPublishedOnlyAfterCleanup": True,
        "cleanupFailureIsRetryable": True,
        "leaseReleasedExactlyOnceOnCommit": True,
    }, "terminal replay policy differs")
    scratch = document["scratch"]
    require(scratch["purpose"] == "SUPPORT_EXPORT"
            and scratch["maximumBytes"] == 1_048_576
            and scratch["maximumLifetimeSeconds"] == 900
            and scratch["protection"] == "COMPLETE", "support scratch bound/protection differs")
    require(scratch["sourcePurposesRejected"] == ["CAPTURE", "IMPORT", "SOURCE"],
            "source scratch isolation differs")
    require(scratch["recovery"]["leaseCollisionFailsClosed"] is True
            and scratch["recovery"]["tombstoneIdentityVerified"] is True
            and scratch["recovery"]["tombstoneCollisionPreservesOriginal"] is True,
            "support scratch recovery differs")
    require(document["bootstrap"]["canonicalStoreOpenCount"] == 0,
            "bootstrap opens canonical store")
    require(document["result"]["networkRequestCount"] == 0
            and document["result"]["automaticUpload"] is False, "export uses network")


def verify_corpus(document: dict[str, Any]) -> None:
    verify_common(document, "corpus", SUPPORT_EXPORT_SCHEMA)
    require(document["fixtureTopLevelFields"] == [
        "schemaVersion", "fixtureIdentity", "clock", "bounds", "metricCompatibility",
        "health", "failureCodes", "unknownFailure", "typedErrorMapping",
        "supportExport", "storeCases", "scratchIsolation", "workflowFriction",
        "logging", "resetErase",
    ], "fixture top-level shape differs")
    require(document["fixtureFailureCodes"] == FAILURE_CODES, "fixture failure codes differ")
    require(document["fixtureTypedErrorMapping"] == TYPED_ERROR_MAPPING,
            "fixture typed error mapping differs")
    require(document["fixtureTypedErrorMappingPolicy"] == TYPED_ERROR_MAPPING_POLICY,
            "fixture typed mapper policy differs")
    require(document["fixtureScratchPurposes"] == SCRATCH_PURPOSES, "fixture scratch purposes differ")
    require(document["fixtureSupportAllowlist"] == SUPPORT_ALLOWLIST, "fixture allowlist differs")
    s2 = document["s2PersistenceRegression"]
    require(
        s2["path"] == EXISTING_PATHS[11]
        and s2["storeSchema"] == "DeviceOperationalSupportStoreSchemaV2"
        and s2["requiredMethods"] == S2_DIAGNOSTICS_TEST_METHODS
        and s2["proofs"] == [
            "exact-zero-canonical-bytes",
            "reloads-every-counter-and-bucket",
            "int64-saturation-without-overflow",
            "malformed-input-resets-only-diagnostics",
            "write-failure-is-non-gating",
            "operational-support-snapshot-reloads",
        ],
        "S2 V2 diagnostics persistence proof differs",
    )
    require(document["exactFiveTestMethods"] is True, "corpus does not require five tests")
    require([row["testMethod"] for row in document["evidence"]] == TEST_METHODS,
            "evidence test methods differ")
    require([row["evidenceID"] for row in document["evidence"]] == EVIDENCE_IDS,
            "evidence IDs differ")
    fixture_path = ROOT / document["fixturePath"]
    if fixture_path.is_file():
        fixture = load(document["fixturePath"])
        require(list(fixture) == document["fixtureTopLevelFields"], "fixture keys differ")
        require(fixture["failureCodes"] == FAILURE_CODES, "fixture code list differs")
        require(fixture["typedErrorMapping"] == TYPED_ERROR_MAPPING,
                "fixture typed error mapping differs")
        require(fixture["supportExport"]["allowlist"] == SUPPORT_ALLOWLIST,
                "fixture allowlist differs")
        require(fixture["metricCompatibility"] == {
            "activeSource": "MXMETRIC_MANAGER_IOS18_FALLBACK",
            "activeSourceCount": 1,
            "betaMetricManagerAdopted": False,
            "futureStableSourceMaySubstitute": True,
            "buildUUID": fixture["metricCompatibility"]["buildUUID"],
        }, "fixture MetricKit compatibility differs")
        require(fixture["bounds"]["supportStoreRecordBytes"] == 16_384
                and fixture["bounds"]["supportStoreTotalBytes"] == 524_288
                and fixture["bounds"]["supportStoreRecordCount"] == 128,
                "fixture support-store bounds differ")
        require(fixture["bounds"]["supportBundleBytes"] == 524_288,
                "fixture support-bundle bound differs")
        require(fixture["bounds"]["scratch"] == SCRATCH_BOUNDS,
                "fixture scratch bounds differ")
        require(fixture["health"]["state"] in HEALTH_STATES
                and len(fixture["health"]["launchBuckets"]) == 4
                and all(value >= 0 for value in fixture["health"]["launchBuckets"]),
                "fixture health bounds differ")
        require(fixture["supportExport"]["networkRequestCount"] == 0
                and fixture["supportExport"]["automaticUploadAllowed"] is False
                and fixture["supportExport"]["externalShareRecallable"] is False
                and fixture["supportExport"]["bootstrapCanonicalStoreOpenCount"] == 0,
                "fixture export boundary differs")
        require(fixture["scratchIsolation"]["rejectedSourcePurposes"] == [
            "CAPTURE", "IMPORT", "SOURCE",
        ] and fixture["scratchIsolation"]["terminalCleanupCount"] == 4
                and fixture["scratchIsolation"]["backupExcluded"] is True,
                "fixture scratch isolation differs")
        require(fixture["workflowFriction"]["enabledByDefault"] is False
                and fixture["workflowFriction"]["productionWriteCount"] == 0
                and fixture["workflowFriction"]["networkRequestCount"] == 0,
                "fixture friction is not disabled")
        require(fixture["resetErase"]["operationalRowsAfterReset"] == 0
                and fixture["resetErase"]["operationalRowsAfterErase"] == 0
                and fixture["resetErase"]["scratchRowsAfterErase"] == 0
                and fixture["resetErase"]["canonicalWorkspaceMutationCount"] == 0,
                "fixture reset/erase boundary differs")


def verify_manifest() -> None:
    manifest = load(MANIFEST)
    verify_seal(manifest, "manifest")
    require(manifest["cardID"] == CARD, "manifest card identity differs")
    require(manifest["authority"] == authority(), "manifest authority differs")
    require(manifest["pathFence"] == PATH_FENCE and manifest["pathFenceCount"] == 27,
            "manifest fence differs")
    require(manifest["artifactCount"] == len(MANIFEST_INPUT_PATHS)
            and manifest["artifactCount"] == 26,
            "manifest sealed input count differs")
    require(manifest["existingPaths"] == EXISTING_PATHS
            and manifest["newPaths"] == NEW_PATHS
            and manifest["toolingPaths"] == TOOL_PATHS, "manifest path partition differs")
    require(manifest["fenceProof"]["pathFenceDigest"] == FENCE_DIGEST
            and manifest["fenceProof"]["priorPathFenceDigest"] == PRIOR_FENCE_DIGEST
            and manifest["fenceProof"]["correctionReceiptDigest"] == FENCE_CORRECTION_RECEIPT_DIGEST
            and manifest["fenceProof"]["correctionTransitionDigest"]
                == TRANSITION_DIGEST
            and manifest["fenceProof"]["priorPathCount"] == 25
            and manifest["fenceProof"]["pathCount"] == 27
            and manifest["fenceProof"]["addedPaths"] == [
                "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
                "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
            ]
            and manifest["fenceProof"]["activeS10Overlap"] is False,
            "manifest fence proof differs")
    require(manifest["fenceProof"]["priorFenceOverlapCount"] == 18
            and manifest["fenceProof"]["authorizedPriorFenceOverlapCount"] == 18
            and manifest["fenceProof"]["unauthorizedPriorFenceOverlapCount"] == 0,
            "manifest overlap proof differs")
    require(manifest["privacyAllowlistOnly"] is True and manifest["noNetwork"] is True,
            "manifest privacy/network claims differ")
    require(manifest["pendingFencePaths"] == [
        path for path in NEW_SOURCE_PATHS if not (ROOT / path).is_file()
    ], "manifest pending source paths differ")
    rows = manifest["artifacts"]
    require([row["path"] for row in rows] == [
        path for path in MANIFEST_INPUT_PATHS
        if (ROOT / path).is_file() or path in GENERATED_PATHS
    ], "manifest artifact closure differs")
    for row in rows:
        path = ROOT / row["path"]
        if path.is_file():
            data = path.read_bytes()
        else:
            data = all_outputs(ROOT)[row["path"]]
        require(row["bytes"] == len(data) and row["sha256"] == sha(data),
                f"manifest source seal differs: {row['path']}")
    require(manifest["artifactSetDigest"] == sha(pretty(rows)), "manifest set digest differs")



# Current Source entry: the historical Card 28 routine and provider documents
# below remain unchanged. Only the five obsolete representation literals at
# these exact three paths are rebound; every other provider token is required.
CURRENT_C08_REBOUND_TOKENS = {
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift": (
        "DeviceOperationalSupportStoreV2",
    ),
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift": (
        "canonicalDiagnosticsZero",
    ),
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift": (
        "cleanupDeferred", "canonicalOperationalSupportData",
        "DeviceOperationalSupportSnapshotV2",
    ),
}


def _current_c08_swift_views(source: str) -> tuple[str, str]:
    """Preserve literal values, but mask comments/strings for code structure."""
    comments = list(source)
    code = list(source)

    def blank(target: list[str], start: int, end: int) -> None:
        for offset in range(start, end):
            if source[offset] not in "\r\n":
                target[offset] = " "

    def comment_end(start: int) -> int:
        if source.startswith("//", start):
            end = source.find("\n", start + 2)
            return len(source) if end < 0 else end
        depth = 1
        index = start + 2
        while index < len(source) and depth:
            if source.startswith("/*", index):
                depth += 1
                index += 2
            elif source.startswith("*/", index):
                depth -= 1
                index += 2
            else:
                index += 1
        require(depth == 0, "current C08: unterminated Swift comment or string")
        return index

    def string_open(start: int) -> tuple[int, int] | None:
        index = start
        while index < len(source) and source[index] == "#":
            index += 1
        if index < len(source) and source[index] == '"':
            return index - start, 3 if source.startswith('"""', index) else 1
        return None

    def interpolation_end(start: int) -> int:
        depth = 1
        index = start
        while index < len(source):
            if source.startswith("//", index) or source.startswith("/*", index):
                index = comment_end(index)
                continue
            opener = string_open(index)
            if opener is not None:
                index = string_end(index, *opener)
                continue
            if source[index] == "(":
                depth += 1
            elif source[index] == ")":
                depth -= 1
                if depth == 0:
                    return index + 1
            index += 1
        require(False, "current C08: unterminated Swift comment or string")
        return len(source)

    def string_end(start: int, hashes: int, quotes: int) -> int:
        closing = '"' * quotes + "#" * hashes
        escape = "\\" + "#" * hashes
        index = start + hashes + quotes
        while index < len(source):
            if source.startswith(closing, index):
                return index + len(closing)
            if source.startswith(escape, index):
                after_escape = index + len(escape)
                if source.startswith("(", after_escape):
                    index = interpolation_end(after_escape + 1)
                else:
                    require(after_escape < len(source),
                            "current C08: unterminated Swift comment or string")
                    index = after_escape + 1
                continue
            require(quotes == 3 or source[index] not in "\r\n",
                    "current C08: unterminated Swift comment or string")
            index += 1
        require(False, "current C08: unterminated Swift comment or string")
        return len(source)

    index = 0
    while index < len(source):
        if source.startswith("//", index) or source.startswith("/*", index):
            end = comment_end(index)
            blank(comments, index, end)
            blank(code, index, end)
            index = end
            continue
        opener = string_open(index)
        if opener is not None:
            end = string_end(index, *opener)
            blank(code, index, end)
            index = end
            continue
        index += 1
    return "".join(comments), "".join(code)


def _current_c08_swift_without_comments(source: str) -> str:
    """Retain actual literal values; code matches use a separate masked view."""
    return _current_c08_swift_views(source)[0]


def _current_c08_code_matches(source: str, token: str, code: str) -> list[int]:
    first = len(token) - len(token.lstrip())
    require(first < len(token), "current C08: empty Source binding token")
    return [
        match.start() for match in re.finditer(re.escape(token), source)
        if code[match.start() + first] == source[match.start() + first]
        and not code[match.start() + first].isspace()
    ]


def _current_c08_tokens(source: str, tokens: tuple[str, ...], label: str) -> None:
    code = _current_c08_swift_views(source)[1]
    require(all(_current_c08_code_matches(source, token, code) for token in tokens),
            f"current C08: {label} wiring differs")
    unreachable = (
        r"\bif\s+(?:false|!\s*true|0\s*==\s*1|1\s*==\s*0)\s*\{",
        r"\bwhile\s+(?:false|!\s*true)\s*\{",
        r"\bguard\s+(?:false|!\s*true)\b",
        r"(?m)^\s*#if\s+(?:false|0)\b",
        r"\bXCTAssertTrue\s*\(\s*true\s*\)",
        r"\bXCTAssertFalse\s*\(\s*false\s*\)",
        r"\bXCTAssertEqual\s*\(\s*(true|false)\s*,\s*\1\s*\)",
    )
    require(not any(re.search(pattern, code) for pattern in unreachable),
            f"current C08: {label} has an explicit unreachable/self-certifying branch")


def _current_c08_balanced_end(code: str, opening: int, label: str) -> int:
    require(0 <= opening < len(code) and code[opening] in "{(",
            f"current C08: {label} declaration structure differs")
    left = code[opening]
    right = "}" if left == "{" else ")"
    depth = 1
    for index in range(opening + 1, len(code)):
        if code[index] == left:
            depth += 1
        elif code[index] == right:
            depth -= 1
            if depth == 0:
                return index + 1
    require(False, f"current C08: {label} declaration structure differs")
    return len(code)


def _current_c08_type(source: str, declaration: str, label: str) -> str:
    code = _current_c08_swift_views(source)[1]
    matches = [
        match for match in re.finditer(
            r"(?m)^" + re.escape(declaration) + r" \{", code,
        )
        if code[:match.start()].count("{") == code[:match.start()].count("}")
    ]
    require(len(matches) == 1, f"current C08: {label} type identity differs")
    match = matches[0]
    end = _current_c08_balanced_end(code, match.end() - 1, label)
    return source[match.start():end]


def _current_c08_function(
    source: str, name: str, tokens: tuple[str, ...], label: str,
) -> str:
    code = _current_c08_swift_views(source)[1]
    members = [
        match for match in re.finditer(
            r"(?m)^    (?:(?:private|fileprivate|internal|public|static|class|final|nonisolated)\s+)*"
            r"func\s+" + re.escape(name) + r"\s*\(", code,
        )
        if code[:match.start()].count("{") - code[:match.start()].count("}") == 1
    ]
    require(len(members) == 1, f"current C08: {label} function identity differs")
    member = members[0]
    parameters_end = _current_c08_balanced_end(code, member.end() - 1, label)
    opening = code.find("{", parameters_end)
    require(opening >= 0 and
            re.fullmatch(
                r"\s*(?:async\b\s*)?(?:(?:throws|rethrows)\b\s*)?"
                r"(?:->\s*[A-Za-z_][A-Za-z0-9_?.<>\[\]:, \t\r\n]*)?\s*",
                code[parameters_end:opening],
            ) is not None and
            re.search(r"\b(?:var|let|func|actor|class|struct|enum|protocol|extension|init|deinit)\b",
                      code[parameters_end:opening]) is None,
            f"current C08: {label} declaration structure differs")
    end = _current_c08_balanced_end(code, opening, label)
    block = source[member.start():end]
    _current_c08_tokens(block, tokens, label)
    return block


def _current_c08_order(source: str, tokens: tuple[str, ...], label: str) -> None:
    code = _current_c08_swift_views(source)[1]
    matches = [_current_c08_code_matches(source, token, code) for token in tokens]
    require(all(len(positions) == 1 for positions in matches) and
            [positions[0] for positions in matches] ==
            sorted(positions[0] for positions in matches),
            f"current C08: {label} order/count differs")


def _verify_current_c08_store(
    diagnostics: str, health: str, catalog: str,
) -> None:
    v2 = _current_c08_type(health, "protocol DeviceOperationalSupportStoreV2: Sendable",
                           "inherited V2 interface")
    _current_c08_tokens(v2, (
        "func operationalSupportSnapshot() async throws -> DeviceOperationalSupportSnapshotV2",
        "func recordOperationalFailure(_ failure: OperationalFailureV1) async throws",
        "func replaceSystemHealth(_ health: SystemHealthDiagnosticsV1) async throws",
        "func resetOperationalSupport() async throws",
    ), "inherited V2 interface")
    v3 = _current_c08_type(
        health, "protocol DeviceOperationalSupportStoreV3: DeviceOperationalSupportStoreV2",
        "V3 extends V2",
    )
    _current_c08_tokens(v3, (
        "func supportFeedbackDraftSnapshot() async throws -> SupportFeedbackDraftStoreSnapshotV1",
        "func supportFeedbackRecoveryCopy() async throws -> Data?",
        "func saveSupportFeedbackDraft(", "expectedRevision: UInt64?",
        "func discardSupportFeedbackDraft(", "expectedDraftID: UUID",
        "expectedRevision: UInt64",
    ), "V3 extends V2")
    schema = _current_c08_type(health, "enum DeviceOperationalSupportStoreSchemaV3",
                               "V3 inherited bounds")
    _current_c08_tokens(schema, (
        "static let version = 3",
        "static let maximumRecordBytes = DeviceOperationalSupportStoreSchemaV2.maximumRecordBytes",
        "static let maximumTotalBytes = DeviceOperationalSupportStoreSchemaV2.maximumTotalBytes",
        "static let maximumRecords = DeviceOperationalSupportStoreSchemaV2.maximumRecords",
        "static let maximumFeedbackDrafts = 1",
    ), "V3 inherited bounds")
    diagnostics_code = _current_c08_swift_views(diagnostics)[1]
    require(len(re.findall(r"(?m)^(?:(?:private|fileprivate|internal|public)\s+)?"
                           r"actor\s+DiagnosticsStore\b", diagnostics_code)) == 1,
            "current C08: sole DiagnosticsStore actor identity differs")
    store = _current_c08_type(
        diagnostics, "actor DiagnosticsStore: DeviceOperationalSupportStoreV3",
        "sole V3 DiagnosticsStore",
    )
    _current_c08_tokens(store, (
        "private static let formatLease = NSRecursiveLock()",
        "DeviceOperationalSupportStoreSchemaV3.maximumRecordBytes",
        "DeviceOperationalSupportStoreSchemaV3.maximumTotalBytes",
        "DeviceOperationalSupportStoreSchemaV3.maximumRecords",
    ), "sole serialized V3 DiagnosticsStore")
    _current_c08_function(store, "operationalSupportSnapshot", (
        "func operationalSupportSnapshot() async throws -> DeviceOperationalSupportSnapshotV2",
        "guard isPrepared, let health else",
        "throw preparationFailure ?? DiagnosticsFailure.invalidFile",
        "return try DeviceOperationalSupportSnapshotV2(health: health, counters: counters)",
    ), "retained V2 snapshot")
    zero = _current_c08_function(store, "isExactlyZero", (
        "return counters == .zero", "health?.state == .unknown",
        "health?.failures.isEmpty == true", "health?.metricKit == nil",
        "feedbackDraft == nil", "&& !feedbackDraftRecoveryRequired",
    ), "complete operational zero")
    _current_c08_tokens(zero, ("prepare()",), "complete operational zero")
    canonical = _current_c08_function(store, "canonicalOperationalSupportEnvelopeDataV3", (
        "guard isPrepared, let health else",
        "throw preparationFailure ?? DiagnosticsFailure.invalidFile",
        "let envelope = try DeviceOperationalSupportEnvelopeV3(",
        "health: health", "counters: counters", "feedbackDraft: feedbackDraft",
        "feedbackDraftRecoveryRequired: feedbackDraftRecoveryRequired",
        "let data = try canonicalData(for: envelope)",
        "guard data.count <= Self.maximumOperationalTotalBytes else",
        "throw DiagnosticsFailure.sizeLimitExceeded", "return data",
    ), "canonical current V3 bytes")
    _current_c08_order(canonical, (
        "let envelope = try DeviceOperationalSupportEnvelopeV3(",
        "let data = try canonicalData(for: envelope)",
        "guard data.count <= Self.maximumOperationalTotalBytes else", "return data",
    ), "canonical current V3 bytes")
    reset_persist = (
        "guard persist(\n            .zero,\n            health: candidate,\n"
        "            feedbackDraft: .some(nil),\n"
        "            feedbackDraftRecoveryRequired: false,\n"
        "            repairExisting: false\n        ) else"
    )
    reset_state = (
        "counters = .zero\n        health = candidate\n        feedbackDraft = nil\n"
        "        feedbackDraftRecoveryRequired = false\n        isPrepared = true\n"
        "        preparationFailure = nil"
    )
    reset = _current_c08_function(store, "resetOperationalSupport", (
        "guard isPrepared || isExplicitRecoveryReset else",
        "throw preparationFailure ?? DiagnosticsFailure.invalidFile",
        "let candidate = try emptyHealth()", "repairExisting: true",
        "try removeFeedbackRecoveryCopyIfPresent()", reset_persist,
        "throw DiagnosticsFailure.invalidFile", reset_state,
    ), "checked current reset")
    _current_c08_order(reset, ("let candidate = try emptyHealth()", reset_persist, reset_state),
                       "checked current reset")
    # Format V3 is an interface/encoding successor of the same registered kind.
    # Rebinding the semantic store name would create a different inventory.
    catalog_type = _current_c08_type(
        catalog, "struct CurrentSyncClassificationCatalogV1: Sendable", "semantic catalog",
    )
    catalog_code = _current_c08_swift_views(catalog_type)[1]
    rule_members = [
        match for match in re.finditer(
            r"(?m)^    static var diagnosticRepresentationRules: "
            r"\[CurrentRepresentationRuleV1\] \{", catalog_code,
        )
        if catalog_code[:match.start()].count("{") -
        catalog_code[:match.start()].count("}") == 1
    ]
    require(len(rule_members) == 1,
            "current C08: diagnostic representation rule identity differs")
    rule_member = rule_members[0]
    rules = catalog_type[rule_member.start():_current_c08_balanced_end(
        catalog_code, rule_member.end() - 1, "diagnostic representation rule",
    )]
    _current_c08_tokens(rules, (
        'name: "DeviceOperationalSupportStoreV2"',
        '.filter { $0 != "DeviceOperationalSupportStoreV2"',
        '&& $0 != "ScratchDataLeaseStoreV1"',
        "source: store",
        "sourceAuthority: .persistedDeviceStore",
        "representationAuthority: .nonpersistentView",
    ), "unchanged persistent kind and nonpersistent views")
    _current_c08_function(catalog_type, "validate", (
        'name: "DeviceOperationalSupportStoreV2"',
        "registration(for: supportStore).replicationPolicy.persistence == .ownedFile",
        "registration(for: rule.representation)",
        ".replicationPolicy.persistence == .nonpersistent",
        ("guard registration.classification == .privateDeviceOnly,\n"
         "                  registration.replicationPolicy.authority == .localDevice,\n"
         "                  registration.replicationPolicy.transport == .excluded,\n"
         "                  registration.replicationPolicy.bootstrap == .destinationLocal,\n"
         "                  route.filesystemBackup == .notApplicable,\n"
         "                  route.semanticBackup == .exclude,\n"
         "                  route.portableExport == .exclude else"),
    ), "unchanged device-local catalog policy")


def _verify_current_c08_erase_zero(erase: str) -> None:
    # The real cleanup is a direct member of a private named extension, not
    # the primary class. Preserve the primary type proof without discarding
    # the rest of the file, then bind exactly one genuine extension member.
    _current_c08_type(erase, "final class EraseAllService", "Erase service owner")
    code = _current_c08_swift_views(erase)[1]
    # Independently close the complete declaration census before selecting
    # the authentic owner. Alternate indentation, overloads in the primary
    # class/other extensions and escaped spellings may not evade uniqueness.
    cleanup_declarations = list(re.finditer(
        r"\bfunc\b\s*(?:completeCleanup\b|`completeCleanup`)", code,
    ))
    require(len(cleanup_declarations) == 1,
            "current C08: checked V3 Erase publication function identity differs")
    candidates = []
    for owner in re.finditer(r"(?m)^private extension EraseAllService \{", code):
        if code[:owner.start()].count("{") != code[:owner.start()].count("}"):
            continue
        end = _current_c08_balanced_end(
            code, owner.end() - 1, "Erase cleanup extension owner")
        owner_code = code[owner.start():end]
        members = [
            member for member in re.finditer(
                r"(?m)^    (?:(?:private|fileprivate|internal|public|static|class|final|nonisolated)\s+)*"
                r"func\s+completeCleanup\s*\(", owner_code,
            )
            if owner_code[:member.start()].count("{") -
            owner_code[:member.start()].count("}") == 1
        ]
        for member in members:
            candidates.append((owner.start(), end, member.start()))
    require(len(candidates) == 1,
            "current C08: checked V3 Erase publication function identity differs")
    owner_start, owner_end, member_start = candidates[0]
    require(cleanup_declarations[0].start() == owner_start + member_start + len("    "),
            "current C08: checked V3 Erase publication function identity differs")
    owner_source, owner_code = erase[owner_start:owner_end], code[owner_start:owner_end]
    signature = (
        "    func completeCleanup(\n"
        "        _ value: EraseIntentV1,\n"
        "        session: StoreGenerationSession,\n"
        "        authority: StoreRestoreGenerationAuthority,\n"
        "        auxiliary: EraseAuxiliaryAuthority,\n"
        "        diagnosticsStore: DiagnosticsStore,\n"
        "        intentStore: EraseIntentStore,\n"
        "        subject: EraseAllOperationSubjectV1,\n"
        "        reservation: AppAccessGateV1.EraseAdoptionToken?\n"
        "    ) async throws -> StoreGenerationSession {"
    )
    require(_current_c08_code_matches(owner_source, signature, owner_code) == [member_start],
            "current C08: checked V3 Erase publication signature identity differs")
    require(_current_c08_hardening_conditions(code, owner_start) == () and
            _current_c08_hardening_conditions(code, owner_start + member_start) == (),
            "current C08: checked V3 Erase publication production ownership differs")
    # The unchanged member extractor checks this owner's direct member and
    # its own closing brace; no token from another method/property can count.
    cleanup = _current_c08_function(owner_source, "completeCleanup", (
        "let replacementDiagnosticsStore = DiagnosticsStore(",
        "applicationSupportURL: applicationSupportURL",
        "try await replacementDiagnosticsStore.resetOperationalSupport()",
        "let diagnosticsZeroSnapshot = try await replacementDiagnosticsStore",
        ".operationalSupportSnapshot()",
        "diagnosticsZeroSnapshot.schemaVersion",
        "== DeviceOperationalSupportStoreSchemaV2.version",
        "diagnosticsZeroSnapshot.counters == .zero",
        "diagnosticsZeroSnapshot.health.failures.isEmpty",
        "let feedbackZeroSnapshot = try await replacementDiagnosticsStore",
        ".supportFeedbackDraftSnapshot()", "feedbackZeroSnapshot.state == .empty",
        "feedbackZeroSnapshot.draft == nil", "!feedbackZeroSnapshot.safeCopyAvailable",
        "let diagnosticsZero = try await replacementDiagnosticsStore",
        ".canonicalOperationalSupportEnvelopeDataV3()",
        "await diagnosticsStore.acceptDescriptorErasedZero()",
        "guard await diagnosticsStore.isExactlyZero()",
        "BackupRestoreService.isEmptyCurrent(session.modelContext)",
        "try auxiliary.verifyTargetsRemovedExceptDiagnostics()",
        "try auxiliary.verifyDiagnostics(\n            expectedData: diagnosticsZero\n        )",
        "let completed = activated.advancing(to: .cleanupComplete)",
        "try intentStore.replace(expected: activated, with: completed)",
        "try auxiliary.verifyDiagnostics(expectedData: diagnosticsZero)",
        "try intentStore.remove(expected: completed)",
        "try auxiliary.removeEraseRootIfEmpty()", "didCompleteErase?(receipt)",
    ), "checked V3 Erase publication")
    _current_c08_order(cleanup, (
        "let replacementDiagnosticsStore = DiagnosticsStore(",
        "try await replacementDiagnosticsStore.resetOperationalSupport()",
        "let diagnosticsZeroSnapshot = try await replacementDiagnosticsStore",
        "let feedbackZeroSnapshot = try await replacementDiagnosticsStore",
        "let diagnosticsZero = try await replacementDiagnosticsStore",
        "await diagnosticsStore.acceptDescriptorErasedZero()",
        "guard await diagnosticsStore.isExactlyZero()",
        "try auxiliary.verifyDiagnostics(\n            expectedData: diagnosticsZero\n        )",
        "let completed = activated.advancing(to: .cleanupComplete)",
        "try intentStore.replace(expected: activated, with: completed)",
        "try auxiliary.verifyDiagnostics(expectedData: diagnosticsZero)",
        "try intentStore.remove(expected: completed)",
        "try auxiliary.removeEraseRootIfEmpty()", "didCompleteErase?(receipt)",
    ), "checked V3 Erase publication")


def _verify_current_c08_s66(tests: str) -> None:
    full_tests = tests
    tests = _current_c08_type(
        tests, "final class S6_6EraseRecoveryTests: XCTestCase", "S66 XCTest owner",
    )
    golden = _current_c08_function(tests,
        "testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState", (
        "try await owner.adoptCompletedReceipt()",
        "try await owner.activateFreshOrdinarySession()",
        "guard case let .ready(fresh, _, _) = owner.router.route else",
        "XCTAssertEqual(fresh.generationID, newID)",
        "XCTAssertNotEqual(try fresh.workspaceWriter.currentRevision().writerInstanceID, oldWriterID)",
        "let operationalAfterErase = try await harness.diagnostics.operationalSupportSnapshot()",
        "XCTAssertEqual(operationalAfterErase.schemaVersion, 2)",
        "XCTAssertEqual(operationalAfterErase.counters, .zero)",
        "XCTAssertTrue(operationalAfterErase.health.failures.isEmpty)",
        "let persistedBytes = try Data(contentsOf: diagnosticsURL)",
        "let reopenedDiagnostics = DiagnosticsStore(applicationSupportURL: harness.support)",
        "let canonicalV3Bytes = try await reopenedDiagnostics",
        ".canonicalOperationalSupportEnvelopeDataV3()",
        "XCTAssertEqual(persistedBytes, canonicalV3Bytes)",
        'JSONSerialization.jsonObject(with: persistedBytes) as? [String: Any]',
        '(persistedEnvelope["schemaVersion"] as? NSNumber)?.intValue,\n            3',
        "counterEncoder.encode(DiagnosticsV1.zero)",
        "XCTAssertEqual(persistedCounters as NSDictionary, expectedCounters as NSDictionary)",
        'XCTAssertNil(persistedEnvelope["feedbackDraft"])',
        '(persistedEnvelope["feedbackDraftRecoveryRequired"] as? NSNumber)?.boolValue,\n            false',
    ), "S66 actual reopened V3 zero")
    _current_c08_order(golden, (
        "try await owner.adoptCompletedReceipt()",
        "try await owner.activateFreshOrdinarySession()",
        "guard case let .ready(fresh, _, _) = owner.router.route else",
        "let operationalAfterErase = try await harness.diagnostics.operationalSupportSnapshot()",
        "let persistedBytes = try Data(contentsOf: diagnosticsURL)",
        "let reopenedDiagnostics = DiagnosticsStore(applicationSupportURL: harness.support)",
        "let canonicalV3Bytes = try await reopenedDiagnostics",
        "XCTAssertEqual(persistedBytes, canonicalV3Bytes)",
        'XCTAssertNil(persistedEnvelope["feedbackDraft"])',
    ), "S66 actual reopened V3 zero")
    live = _current_c08_function(tests, "testLiveCleanupWaitsForOldContextReferenceDrain", (
        "let operation = try owner.originalOperationForInterruption()",
        "try await owner.prepareCompatibility(service: service,",
        "harness.coordinator = nil", "return (operation, oldID)",
        "XCTAssertNotNil(retainedContext)", "XCTAssertNotNil(retainedContainer)",
        "let cleanupAdvancedWhileHeld = try await operation.advanceCleanup()",
        "XCTAssertFalse(cleanupAdvancedWhileHeld)",
        "XCTAssertEqual(completedReceipts.count, 0)",
        ("XCTAssertEqual(try operation\n"
         "                .requirePublishedTargetForV949Fixture(), newID)"),
        ("XCTAssertTrue(fileManager.fileExists(\n"
         "                atPath: harness.factory.installedGenerationURL(id: oldID).path\n"
         "            ))"),
        "retainedContext = nil", "retainedContainer = nil",
        "guard observedOldContext == nil, observedOldContainer == nil else",
        "throw V23EraseOperationHarnessV1.Failure.drainPending",
        "try await owner.completeCleanup()", "XCTAssertEqual(completedReceipts.count, 1)",
        "XCTAssertEqual(completedReceipts.first?.subject.newGenerationID, newID)",
        "try await owner.adoptCompletedReceipt()",
        "try await owner.activateFreshOrdinarySession()",
        "guard case let .ready(reopened, _, _) = owner.router.route else",
        "XCTAssertEqual(reopened.generationID, newID)",
        ("XCTAssertFalse(fileManager.fileExists(\n"
         "                atPath: harness.factory.installedGenerationURL(id: oldID).path\n"
         "            ))"),
    ), "S66 held-reader live drain")
    _current_c08_order(live, (
        "let cleanupAdvancedWhileHeld = try await operation.advanceCleanup()",
        "XCTAssertFalse(cleanupAdvancedWhileHeld)",
        "XCTAssertEqual(completedReceipts.count, 0)",
        ("XCTAssertEqual(try operation\n"
         "                .requirePublishedTargetForV949Fixture(), newID)"),
        ("XCTAssertTrue(fileManager.fileExists(\n"
         "                atPath: harness.factory.installedGenerationURL(id: oldID).path\n"
         "            ))"),
        "retainedContext = nil", "retainedContainer = nil",
        "guard observedOldContext == nil, observedOldContainer == nil else",
        "try await owner.completeCleanup()", "XCTAssertEqual(completedReceipts.count, 1)",
        "try await owner.adoptCompletedReceipt()",
        "try await owner.activateFreshOrdinarySession()",
        "guard case let .ready(reopened, _, _) = owner.router.route else",
        ("XCTAssertFalse(fileManager.fileExists(\n"
         "                atPath: harness.factory.installedGenerationURL(id: oldID).path\n"
         "            ))"),
    ), "S66 held-reader live drain")
    cold = _current_c08_function(tests, "testRetainedLiveContextDefersCleanupUntilColdRecovery", (
        "XCTAssertTrue(outcome.operation === eraseOperation)",
        "XCTAssertTrue(outcome.operation.detached)",
        "XCTAssertTrue(outcome.operation.hasPreparedCleanup)",
        "XCTAssertEqual(pending.phase, .sessionActivated)",
        "XCTAssertEqual(initialCompletionCount, 0)",
        "XCTAssertTrue(pristineOutcome.operation === pristineOperation)",
        "XCTAssertTrue(pristineOutcome.operation.detached)",
        "XCTAssertTrue(pristineOutcome.operation.hasPreparedCleanup)",
        "XCTAssertEqual(pristineInitialCompletions, 0)",
        "XCTAssertEqual(pristinePending.phase, .sessionActivated)",
        ("XCTAssertTrue(fileManager.fileExists(atPath:\n"
         "                pristine.factory.installedGenerationURL(\n"
         "                    id: pristineOldID).path))"),
        ".beginPristinePreparedEraseColdRestartForTesting(",
        "pristineCoordinator = nil", "pristine.coordinator = nil",
        "pristineContext = nil", "pristineContainer = nil",
        ".finishPristinePreparedEraseColdRestartForTesting(",
        "let recovery = EraseAllService(",
        "let recovered = try await startKernelColdOwner(",
        "XCTAssertEqual(recovered.generationID, pristineNewID)",
        "XCTAssertEqual(recoveryReceipts.map(\\.subject.eraseID),\n                [pristinePending.eraseID])",
        "XCTAssertEqual(recoveryReceipts.map(\\.subject.newGenerationID),\n                [pristineNewID])",
        ("XCTAssertFalse(fileManager.fileExists(atPath:\n"
         "                pristine.factory.installedGenerationURL(id: pristineOldID).path\n"
         "            ))"),
        ('XCTAssertFalse(fileManager.fileExists(atPath:\n'
         '                pristine.support.appendingPathComponent("FieldEvidenceErase").path\n'
         '            ))'),
        "let diagnosticsAfterRecovery = await pristine.diagnostics.snapshot()",
        "XCTAssertEqual(diagnosticsAfterRecovery, .zero)",
    ), "S66 genuine cold recovery")
    # Two real original owners share this method. The earlier original was
    # deliberately rewritten and must refuse; only the pristine original may
    # perform the positive cold restart. Bind both to their actual outer-do
    # statement path, rather than counting a shared member name over the method.
    code = _current_c08_swift_views(cold)[1]
    require(not re.search(r"(?m)^[ \t]*#(?:if|elseif|else|endif)\b", code),
            "current C08: S66 cold scenario conditional ownership differs")
    full_code = _current_c08_swift_views(full_tests)[1]
    method_positions = _current_c08_code_matches(full_tests, cold, full_code)
    require(len(method_positions) == 1,
            "current C08: S66 cold scenario method ownership differs")
    directives = []
    for directive in re.finditer(
        r"(?m)^[ \t]*#(if|elseif|else|endif)\b[^\n]*",
        full_code[:method_positions[0]],
    ):
        kind = directive.group(1)
        if kind == "if":
            directives.append(directive.start())
        elif kind == "endif":
            require(bool(directives),
                    "current C08: S66 cold scenario conditional ownership differs")
            directives.pop()
        else:
            require(bool(directives),
                    "current C08: S66 cold scenario conditional ownership differs")
    require(not directives,
            "current C08: S66 cold scenario conditional ownership differs")
    function_open = code.find("{")
    outer = list(re.finditer(r"(?m)^        do \{", code))
    require(len(outer) == 1 and cold[:outer[0].end()] == (
        '    func testRetainedLiveContextDefersCleanupUntilColdRecovery() async throws {\n'
        '        var diagnosticPhase = "harness"\n'
        '        do {'
    ), "current C08: S66 cold scenario outer-do identity differs")
    outer_open = outer[0].end() - 1
    outer_end = _current_c08_balanced_end(code, outer_open, "S66 cold scenario outer-do")

    def statement_owner(position: int) -> bool:
        stack = []
        opening_for = {"}": "{", ")": "(", "]": "["}
        for index, character in enumerate(code[:position]):
            if character in "{([":
                stack.append((character, index))
            elif character in "})]":
                if not stack or stack[-1][0] != opening_for[character]:
                    return False
                stack.pop()
        return stack == [("{", function_open), ("{", outer_open)]

    preparation_tokens = (
        'let harness = try await makeHarness("deferred-drain", diagnoseInitialOpen: true,\n                observePhase: { diagnosticPhase = $0 })',
        'var coordinator: StoreSessionCoordinator? = try XCTUnwrap(harness.coordinator)',
        'let oldID = try XCTUnwrap(coordinator).generationID',
        'let owner = harness.originalOwner',
        'try await owner.admit(coordinator: try XCTUnwrap(coordinator))',
        'let eraseOperation = try owner.originalOperationForInterruption()',
        'let newID = uuid("66000000-0000-0000-0000-000000000111")',
        'var retainedContext: ModelContext? = try XCTUnwrap(coordinator).modelContext',
        'var retainedContainer: ModelContainer? =\n                try XCTUnwrap(coordinator).modelContext.container',
        'var initialCompletionCount = 0',
        'let service = try owner.configure(EraseAllService(\n                applicationSupportURL: harness.support,\n                cachesDirectoryURL: harness.caches,\n                temporaryDirectoryURL: harness.temporary,\n                userDefaults: harness.defaults,\n                bundleIdentifier: bundleID,\n                makeUUID: sequence([\n                    newID,\n                    uuid("66000000-0000-0000-0000-000000000112"),\n                ]),\n                admitErase: { try await owner.admitSubject($0) },\n                didCompleteErase: { _ in initialCompletionCount += 1 }\n            ))',
        'service.enableOriginalColdExitWitnessForTesting = true',
        'Self.retainedS6EraseServices.append((harness.root, service))',
        'service.erasePhaseDiagnosticForTesting = { diagnosticPhase = $0 }',
        'diagnosticPhase = "erase-with-retained-context"',
        'var activationFailure: Error?',
        'let outcome = try await service.erase(\n                confirmation: "ERASE",\n                coordinator: try XCTUnwrap(coordinator),\n                diagnosticsStore: harness.diagnostics,\n                operation: eraseOperation,\n                activate: { [weak coordinator, weak router = owner.router] session in\n                    do {\n                        guard let coordinator, let router else {\n                            throw FixtureError.invalid\n                        }\n                        try router.activateErasePreparationSession(\n                            session, coordinator: coordinator,\n                            operation: eraseOperation)\n                    } catch {\n                        activationFailure = error\n                    }\n                })',
        'if let activationFailure { throw activationFailure }',
        'diagnosticPhase = "post-erase-assertions"',
        'XCTAssertTrue(outcome.operation === eraseOperation)',
        'XCTAssertTrue(outcome.operation.detached)',
        'XCTAssertTrue(outcome.operation.hasPreparedCleanup)',
        'XCTAssertEqual(try XCTUnwrap(coordinator).generationID, newID)',
        'let preparedContext = try XCTUnwrap(coordinator).modelContext',
        'XCTAssertEqual(try eraseOperation\n                .requirePublishedTargetForV949Fixture(), newID)',
        'XCTAssertTrue(fileManager.fileExists(atPath:\n                harness.factory.installedGenerationURL(id: oldID).path\n            ))',
        'let pending = try XCTUnwrap(try EraseIntentStore(\n                applicationSupportURL: harness.support\n            ).load())',
        'XCTAssertEqual(pending.phase, .sessionActivated)',
        'XCTAssertEqual(initialCompletionCount, 0)',
    )
    refusal_tokens = (
        'diagnosticPhase = "same-root-physical-identity-refusal"',
        'let beforeRefusalFiles = try tree(harness.support)',
        'let beforeRefusalDefaults =\n                harness.defaults.persistentDomain(\n                    forName: harness.defaultsSuiteName) as NSDictionary?',
        'XCTAssertThrowsError(\n                try owner.router.beginPristinePreparedEraseColdRestartForTesting(\n                    eraseOperation, originalService: service)\n            ) { error in\n                XCTAssertEqual(error as? EraseAllServiceError,\n                    .invalidAuthority)\n            }',
        'XCTAssertEqual(initialCompletionCount, 0)',
        'XCTAssertEqual(try EraseIntentStore(\n                applicationSupportURL: harness.support).load(), pending)',
        'XCTAssertEqual(try tree(harness.support), beforeRefusalFiles)',
        'XCTAssertEqual(harness.defaults.persistentDomain(\n                forName: harness.defaultsSuiteName) as NSDictionary?,\n                beforeRefusalDefaults)',
        'XCTAssertTrue(try owner.router.eraseRetirementOperation(\n                for: owner.originalTicketForInterruption())\n                === eraseOperation)',
        'XCTAssertTrue(fileManager.fileExists(atPath:\n                harness.factory.installedGenerationURL(id: oldID).path))',
    )
    positive_tokens = (
        'let pristine = try await makeHarness("deferred-drain-pristine",\n                diagnoseInitialOpen: true,\n                observePhase: { diagnosticPhase = $0 })',
        'defer { cleanup(pristine) }',
        'let pristineOwner = pristine.originalOwner',
        'var pristineCoordinator: StoreSessionCoordinator? =\n                try XCTUnwrap(pristine.coordinator)',
        'let pristineOldID = try XCTUnwrap(pristineCoordinator).generationID',
        'let pristineNewID = uuid("66000000-0000-0000-0000-000000000113")',
        'var pristineContext: ModelContext? =\n                try XCTUnwrap(pristineCoordinator).modelContext',
        'var pristineContainer: ModelContainer? =\n                try XCTUnwrap(pristineCoordinator).modelContext.container',
        'try await pristineOwner.admit(\n                coordinator: try XCTUnwrap(pristineCoordinator))',
        'let pristineOperation =\n                try pristineOwner.originalOperationForInterruption()',
        'var pristineInitialCompletions = 0',
        'let pristineService = try pristineOwner.configure(EraseAllService(\n                applicationSupportURL: pristine.support,\n                cachesDirectoryURL: pristine.caches,\n                temporaryDirectoryURL: pristine.temporary,\n                userDefaults: pristine.defaults,\n                bundleIdentifier: bundleID,\n                makeUUID: sequence([pristineNewID, UUID()]),\n                admitErase: { try await pristineOwner.admitSubject($0) },\n                didCompleteErase: { _ in pristineInitialCompletions += 1 }\n            ))',
        'pristineService.enableOriginalColdExitWitnessForTesting = true',
        'Self.retainedS6EraseServices.append(\n                (pristine.root, pristineService))',
        'var pristineActivationFailure: Error?',
        'diagnosticPhase = "pristine-original-preparation"',
        'let pristineOutcome = try await pristineService.erase(\n                confirmation: "ERASE",\n                coordinator: try XCTUnwrap(pristineCoordinator),\n                diagnosticsStore: pristine.diagnostics,\n                operation: pristineOperation,\n                activate: {\n                    [weak pristineCoordinator,\n                     weak router = pristineOwner.router] session in\n                    do {\n                        guard let pristineCoordinator, let router else {\n                            throw FixtureError.invalid\n                        }\n                        try router.activateErasePreparationSession(\n                            session, coordinator: pristineCoordinator,\n                            operation: pristineOperation)\n                    } catch {\n                        pristineActivationFailure = error\n                    }\n                })',
        'if let pristineActivationFailure {\n                throw pristineActivationFailure\n            }',
        'XCTAssertTrue(pristineOutcome.operation === pristineOperation)',
        'XCTAssertTrue(pristineOutcome.operation.detached)',
        'XCTAssertTrue(pristineOutcome.operation.hasPreparedCleanup)',
        'XCTAssertEqual(try XCTUnwrap(pristineCoordinator).generationID,\n                pristineNewID)',
        'XCTAssertEqual(pristineInitialCompletions, 0)',
        'XCTAssertTrue(fileManager.fileExists(atPath:\n                pristine.factory.installedGenerationURL(\n                    id: pristineOldID).path))',
        'let pristinePending = try XCTUnwrap(try EraseIntentStore(\n                applicationSupportURL: pristine.support).load())',
        'XCTAssertEqual(pristinePending.phase, .sessionActivated)',
        'let pristineReservation =\n                try pristineOwner.originalReservationForInterruption()',
        'try pristineOwner.router\n                .beginPristinePreparedEraseColdRestartForTesting(\n                    pristineOperation, originalService: pristineService)',
        'pristineCoordinator = nil',
        'pristine.coordinator = nil',
        'pristineContext = nil',
        'pristineContainer = nil',
        'try await pristineOwner.router\n                .finishPristinePreparedEraseColdRestartForTesting(\n                    pristineOperation,\n                    subject: pristineReservation.subject,\n                    reservation: pristineReservation)',
        'var recoveryReceipts = [CompletedEraseReceiptV1]()',
        'diagnosticPhase = "startup-reconcile-after-context-release"',
        'let recovery = EraseAllService(\n                applicationSupportURL: pristine.support,\n                cachesDirectoryURL: pristine.caches,\n                temporaryDirectoryURL: pristine.temporary,\n                userDefaults: pristine.defaults,\n                bundleIdentifier: bundleID,\n                didCompleteErase: { recoveryReceipts.append($0) }\n            )',
        'recovery.erasePhaseDiagnosticForTesting = { diagnosticPhase = $0 }',
        'let recovered = try await startKernelColdOwner(\n                pristine, service: recovery)',
        'diagnosticPhase = "post-recovery-assertions"',
        'XCTAssertEqual(recovered.generationID, pristineNewID)',
        'XCTAssertEqual(recoveryReceipts.map(\\.subject.eraseID),\n                [pristinePending.eraseID])',
        'XCTAssertEqual(recoveryReceipts.map(\\.subject.newGenerationID),\n                [pristineNewID])',
        'XCTAssertFalse(fileManager.fileExists(atPath:\n                pristine.factory.installedGenerationURL(id: pristineOldID).path\n            ))',
        'XCTAssertFalse(fileManager.fileExists(atPath:\n                pristine.support.appendingPathComponent("FieldEvidenceErase").path\n            ))',
        'let diagnosticsAfterRecovery = await pristine.diagnostics.snapshot()',
        'XCTAssertEqual(diagnosticsAfterRecovery, .zero)',
    )
    anchors = [_current_c08_code_matches(cold, tokens[0], code)
               for tokens in (refusal_tokens, positive_tokens)]
    require(all(len(positions) == 1 for positions in anchors),
            "current C08: S66 cold scenario identity differs")
    refusal_start, positive_start = (positions[0] for positions in anchors)
    require(outer_open < refusal_start < positive_start < outer_end - 1 and
            statement_owner(refusal_start) and statement_owner(positive_start),
            "current C08: S66 cold scenario statement ownership differs")
    begin_calls = _current_c08_code_matches(
        cold, ".beginPristinePreparedEraseColdRestartForTesting(", code,
    )
    finish_calls = _current_c08_code_matches(
        cold, ".finishPristinePreparedEraseColdRestartForTesting(", code,
    )
    require(len(begin_calls) == 2 and len(finish_calls) == 1,
            "current C08: S66 two-original cold call census differs")
    # Join every protected occurrence in the comment-masked body, including
    # strings, escaped spellings, function values and interpolation, to these exact
    # genuine calls. Current Source contains no other occurrence; conservative
    # lexical refusal avoids pretending the string view parses interpolation.
    for name, calls in (
        ("beginPristinePreparedEraseColdRestartForTesting", begin_calls),
        ("finishPristinePreparedEraseColdRestartForTesting", finish_calls),
    ):
        references = [match.start() for match in re.finditer(
            r"(?<!\w)" + re.escape(name) + r"(?!\w)", cold,
        )]
        require(references == [position + 1 for position in calls],
                "current C08: S66 protected cold reference census differs")

    def method_exit(position: int) -> bool:
        stack = []
        opening_for = {"}": "{", ")": "(", "]": "["}
        for index, character in enumerate(code[:position]):
            if character in "{([":
                callable_body = False
                if character == "{" and index != function_open:
                    head = code[:index].rstrip()
                    # These are expression closures or explicit callable
                    # parameter headers, not ordinary if/do/loop bodies.
                    callable_body = head.endswith(("=", ":")) or re.match(
                        r"\s*(?:\[[^\]]*\]\s*)?"
                        r"[A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*"
                        r"[A-Za-z_][A-Za-z0-9_]*)*\s+in\b",
                        code[index + 1:],
                    ) is not None or re.search(
                        r"\bfunc\s+[A-Za-z_][A-Za-z0-9_]*\s*\([^{}]*\)"
                        r"\s*(?:async\s*)?(?:throws\s*)?(?:->[^{}]+)?$", head,
                    ) is not None
                stack.append((character, callable_body))
            elif character in "})]":
                if not stack or stack[-1][0] != opening_for[character]:
                    return True
                stack.pop()
        # An ordinary nested conditional/loop does not change the callable
        # whose return exits. A clear closure/local-function boundary does.
        return not any(callable_body for _, callable_body in stack)

    require(not any(method_exit(outer_open + match.start()) for match in re.finditer(
        r"\breturn\b", code[outer_open:outer_end - 1],
    )), "current C08: S66 cold scenario early return differs")
    for begin, stop, tokens, label in (
        (outer_open + 1, refusal_start, preparation_tokens, "S66 rewritten original preparation"),
        (refusal_start, positive_start, refusal_tokens, "S66 prior physical-identity refusal"),
        (positive_start, outer_end - 1, positive_tokens, "S66 genuine cold recovery"),
    ):
        scenario = cold[begin:stop]
        scenario_code = code[begin:stop]
        _current_c08_order(scenario, tokens, label)
        for token in tokens:
            position = _current_c08_code_matches(scenario, token, scenario_code)[0]
            require(statement_owner(begin + position),
                    f"current C08: {label} statement ownership differs")



def verify_current_source_bindings() -> None:
    """Complete current bindings; historical cards and hardening stay separate."""
    documents = (
        (system_health_contract(), "system health"),
        (lifecycle_contract(), "lifecycle"),
        (support_export_contract(), "support export"),
        (corpus_contract(), "corpus"),
    )
    paths = tuple(EXISTING_PATHS + NEW_SOURCE_PATHS)
    require(len(paths) == len(set(paths)) == 15,
            "current C08: complete fifteen-path census differs")
    require(CURRENT_C08_REBOUND_TOKENS == {
        EXISTING_PATHS[0]: ("DeviceOperationalSupportStoreV2",),
        EXISTING_PATHS[7]: ("canonicalDiagnosticsZero",),
        EXISTING_PATHS[9]: ("cleanupDeferred", "canonicalOperationalSupportData",
                            "DeviceOperationalSupportSnapshotV2"),
    },
            "current C08: closed five-token rebinding census differs")
    texts = {}
    for relative in paths:
        path = ROOT / relative
        require(path.is_file(), f"current C08: missing source {relative}")
        texts[relative] = path.read_text(encoding="utf-8")
    baseline = documents[0][0]["sourceBindings"]
    for document, name in documents:
        bindings = document["sourceBindings"]
        require(type(bindings) is list and bindings == baseline and
                tuple(binding["path"] for binding in bindings) == paths,
                f"current C08: {name} complete binding table differs")
        for binding in bindings:
            require(type(binding) is dict and
                    set(binding) == {"path", "owner", "symbols", "requiredTokens"} and
                    binding["owner"] == CARD and
                    type(binding["symbols"]) is list and
                    all(type(symbol) is str for symbol in binding["symbols"]) and
                    type(binding["requiredTokens"]) is list and
                    all(type(token) is str for token in binding["requiredTokens"]),
                    f"current C08: {name} binding shape differs")
            relative = binding["path"]
            rebound = (CURRENT_C08_REBOUND_TOKENS[relative]
                       if relative in CURRENT_C08_REBOUND_TOKENS else ())
            require(all(binding["requiredTokens"].count(token) == 1 for token in rebound),
                    f"current C08: {name} original rebound token identity differs: {relative}")
            for token in binding["requiredTokens"]:
                if token not in rebound:
                    require(token in texts[relative] or relative == NEW_SOURCE_PATHS[2],
                            f"{name}: missing source token {token}: {relative}")
    # The exact old literals above are accepted only with these complete current
    # interface/publication/reopen/drain proofs; no filewide missing-token waiver.
    swift = {relative: _current_c08_swift_without_comments(texts[relative])
             for relative in (EXISTING_PATHS[0], EXISTING_PATHS[7], EXISTING_PATHS[8],
                              EXISTING_PATHS[9], NEW_SOURCE_PATHS[0])}
    _verify_current_c08_store(swift[EXISTING_PATHS[0]], swift[NEW_SOURCE_PATHS[0]],
                              swift[EXISTING_PATHS[8]])
    _verify_current_c08_erase_zero(swift[EXISTING_PATHS[7]])
    _verify_current_c08_s66(swift[EXISTING_PATHS[9]])


# Additive C86 complete current hardening; historical/C84 definitions below and above remain exact.
CURRENT_C08_HARDENING_SUPPORT_PATHS = ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
 'FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift',
 'FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift',
 'FieldEvidenceApp/Domain/Scheduling/ScheduleOverrideContractsV1.swift',
 'FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift')

CURRENT_C08_HARDENING_DECLARATIONS = (('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '        static func open(\n'
  '            applicationSupportURL: URL,\n'
  '            diagnosticsURL: URL,\n'
  '            fileManager: FileManager,\n'
  '            createIfMissing: Bool\n'
  '        ) throws -> PinnedDiagnosticsAuthority? {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',
   '    private final class PinnedDiagnosticsAuthority {'),
  2,
  5443,
  '64f4beee657db7deaabd6316192357b50901e1a988522a2a411be3c5d66e491c',
  (),
  (('print', 427, ('if DEBUG',)),),
  ('return nil',
   'throw DiagnosticsFailure.invalidFile',
   'guard Darwin.fstat(',
   'guard !diagnosticsName.isEmpty,',
   'guard createIfMissing else {',
   'guard Darwin.mkdirat(',
   'guard Darwin.fsync(applicationSupportDescriptor) == 0 else {',
   'guard diagnosticsDescriptor >= 0 else {'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    func prepare() {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  5481,
  '3161e5e53b22e9bb805c6ca1afb5b8b46733a1cf22f74d14186b4ccbee36b3a4',
  (),
  (('optionalTry', 4513, ()),),
  ('guard !isPrepared else {',
   'guard let authority = try PinnedDiagnosticsAuthority.open(',
   'guard persist(.zero, health: initialHealth) else { return }',
   'preparationFailure = nil',
   'guard let identity = try fileIdentityIfPresent(',
   '} catch let failure as ProtectedFilePolicyError',
   'feedbackDraftRecoveryRequired = decoded.feedbackDraftRecoveryRequired',
   'guard persist(counters, health: decoded.health) else {',
   'preparationFailure = .protectedDataUnavailable',
   '} catch DiagnosticsFailure.unsupportedVersion {',
   'preparationFailure = .unsupportedVersion',
   '} catch DiagnosticsFailure.recoveryRequired {',
   'feedbackDraftRecoveryRequired: true,',
   'feedbackDraftRecoveryRequired = true',
   'preparationFailure = .recoveryRequired',
   '} catch {',
   'preparationFailure = .invalidFile'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    func supportFeedbackDraftSnapshot() async throws -> SupportFeedbackDraftStoreSnapshotV1 {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  932,
  '66a3cbccacb43573479ba1bcc9e49355f0123a7ecd11049162dcc05b57fb2319',
  (),
  (('optionalTry', 364, ()),),
  ('if preparationFailure == .recoveryRequired || feedbackDraftRecoveryRequired {',
   'guard isPrepared else {',
   'throw preparationFailure ?? DiagnosticsFailure.invalidFile'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    private func persist(\n'
  '        _ candidate: DiagnosticsV1,\n'
  '        health healthCandidate: SystemHealthDiagnosticsV1? = nil,\n'
  '        feedbackDraft feedbackDraftCandidate: SupportFeedbackDraftV1?? = nil,\n'
  '        feedbackDraftRecoveryRequired recoveryCandidate: Bool? = nil,\n'
  '        repairExisting: Bool = false\n'
  '    ) -> Bool {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  15466,
  '88045ebb8f9e692804a4216e5139b1841fa523d7fb0742cff0a10e0b8601df61',
  (),
  (('optionalTry', 12789, ()),
   ('optionalTry', 14640, ()),
   ('optionalTry', 14855, ()),
   ('optionalTry', 15165, ()),
   ('print', 12216, ('if DEBUG',))),
  ('let quarantineURL = directoryURL.appendingPathComponent(',
   'Self.quarantineName,',
   'guard let openedAuthority = try PinnedDiagnosticsAuthority.open(',
   'throw DiagnosticsFailure.invalidFile',
   'feedbackDraftRecoveryRequired: recoveryCandidate',
   '?? feedbackDraftRecoveryRequired',
   'let data = try canonicalData(for: state)',
   'canonicalData(for: privacyState)',
   'guard data.count <= Self.maximumOperationalTotalBytes else {',
   'throw DiagnosticsFailure.sizeLimitExceeded',
   'guard let temporaryIdentity else {',
   'guard try readData(',
   'throw DiagnosticsFailure.concurrentMutation',
   'guard try fileIdentityIfPresent(',
   'guard let publishedBackupIdentity = try fileIdentityIfPresent(',
   'guard let replacementIdentity else {',
   'at: quarantineURL,',
   'try fileManager.moveItem(at: backupURL, to: quarantineURL)',
   'at: quarantineURL',
   'let quarantineIdentity = try fileIdentity(',
   'expected: quarantineIdentity,',
   '} catch {',
   'return false'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    private func isIdentity(\n'
  '        _ expected: FileIdentity,\n'
  '        at url: URL,\n'
  '        authorityCheck: () throws -> Void = {}\n'
  '    ) -> Bool {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  348,
  '975407c360789d7da550a712d360e11ca8e5a12920569e3221dc617bbd33da8e',
  (),
  (('optionalTry', 174, ()),),
  ('guard let actual = try? fileIdentity(', 'return false'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    private func feedbackRecoveryCopyExists() throws -> Bool {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  594,
  '5768340ae5b851f84029b6baa5dcbfe7d9fd42224328cb3944329f898849735c',
  (),
  (),
  ('guard let authority = try PinnedDiagnosticsAuthority.open(',
   ') else { return false }',
   'Self.quarantineName,'),
  ('Held/checked recovery-copy probe; no success on failure',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    private func decodeOperationalStore(\n'
  '        _ data: Data\n'
  '    ) throws -> DeviceOperationalSupportEnvelopeV3 {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  2953,
  '280778770bc344357db5a06b45f3933c69bb8f88e1b8610d9b84c9799005b147',
  (),
  (('optionalTry', 1746, ()), ('optionalTry', 1838, ()), ('optionalTry', 1878, ())),
  ('throw DiagnosticsFailure.unsupportedVersion',
   '} catch DiagnosticsFailure.unsupportedVersion {',
   '} catch {',
   'guard try canonicalData(for: value) == data,',
   'throw DiagnosticsFailure.invalidFile',
   '} catch DiagnosticsFailure.invalidFile {',
   'throw DiagnosticsFailure.recoveryRequired',
   '(try? canonicalData(for: v2)) == data {',
   'feedbackDraftRecoveryRequired: false',
   'guard legacy.isValid, try canonicalData(for: legacy) == data else {',
   '} catch DiagnosticsFailure.recoveryRequired {'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    private func schemaVersion(in data: Data) -> Int? {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  278,
  '7500cf64ea1d48382d026f03b27300850045b52c00c95d14e2ce6466cb5224b9',
  (),
  (('optionalTry', 87, ()),),
  ('guard let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],',
   'let version = dictionary["schemaVersion"] as? NSNumber else { return nil }'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    private func emptyHealth() throws -> SystemHealthDiagnosticsV1 {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  118,
  '59a65245bde81ed26e515ab0bf809ef60a60eaef0d4a3fcf610874de6ef4b513',
  (),
  (),
  (),
  ('Checked empty-health constructor and fixed catalog authority',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    private nonisolated static func makeEmptyHealth(\n'
  '        at date: Date\n'
  '    ) throws -> SystemHealthDiagnosticsV1 {',
  ('actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {',),
  1,
  286,
  '37320b891ea1d71e7e5f72a3fd2ad3df064a853d2dcb4a80a9c87d04a79ed291',
  (),
  (),
  (),
  ('Complete checked system-health construction, not an empty-success fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    static func project(_ boundary: String) -> String {',
  ('enum ColdDiagnosticsBoundaryLabelV1 {',),
  1,
  1460,
  '7c7dfbcf2adfc624cc4b54d1f047a05c84ba52e1afbdfeb8aab8d30aac7b2c6c',
  ('if DEBUG',),
  (),
  (),
  ('DEBUG closed primitive label projection; default unclassified; no associated values',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift',
  '    func performChecked() throws -> ColdDiagnosticsCheckedReceiptV1 {',
  ('@MainActor\nfinal class ColdDiagnosticsCheckedIOV1 {',),
  1,
  8395,
  '77dc34330383b05576bd414b2577a3ab36f2a634e60838fc64045f8f3857dc2b',
  (),
  (('print', 8057, ('if DEBUG',)),),
  ('guard state == .registered, !frameEntered, resources.isEmpty, receipt == nil else {',
   'throw DiagnosticsFailure.invalidFile',
   'guard candidate.applicationSupportURL.isFileURL, candidate.diagnosticsURL.isFileURL,',
   'guard issuer.expectedPrefix == .completedObservation else {',
   'guard issuer.expectedPrefix != .completedObservation else {',
   'guard let image = currentImage, image.directoryFact != nil else {',
   'guard stack.isEmpty, observer == nil, enumeration == nil, policyScope == nil,',
   'policyObservationScope == nil, uncertainPolicyObservationScope == nil else {',
   'guard try held(descriptor(temporary)) == final.leaves[0].fact else {',
   'guard try held(descriptor(current)) == final.leaves[0].fact else {',
   'guard let directory else { throw DiagnosticsFailure.invalidFile }',
   'guard try held(rootFD) == final.directoryFact,',
   'throw DiagnosticsFailure.concurrentMutation',
   'guard resources.allSatisfy({ $0.state == .closed && $0.closeResult == 0',
   'uncertainPolicyObservationScope == nil,',
   'uncertainPolicyDescriptors.isEmpty else {',
   '} catch {',
   'poison()',
   'throw error'),
  ('Checked canonical/legacy decode; explicit recovery-required and failure-false state; owned cleanup; '
   'literal DEBUG boundary or stateless closed projection.',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct LaunchTimeMillisecondsV1: Codable, Equatable, Sendable {',),
  1,
  160,
  '15e21fe69ade17ba18465c84f3fa1ff55ac311ac22c6f1b6eef605f7dc91fb50',
  (),
  (),
  (),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct MetricKitSummaryV1: Codable, Equatable, Sendable {',),
  1,
  197,
  '0ef146c0e28d5c68f99266ac2a883d8ab66be0e84cfd86af94ba38c773974ef2',
  (),
  (),
  ('&& (launchTimeMilliseconds?.isValid ?? true)',),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct WorkPacketDiagnosticSummaryV1: Codable, Equatable, Sendable {',),
  1,
  530,
  'e2bd647f63ef430a15848bf17c9504babac0c1d12db13853fdf0c20d472bfb2b',
  (),
  (),
  (),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct PlanDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  616,
  'ac4898c256117d2708cae5dee164a1c3fefda4bb64c58c2d4f9b3e06cd72638a',
  (),
  (),
  (),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct PlacementPoseDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  370,
  '277ac280ec70807498478c630f5081bbf1547e4dd02c4d0f44439b871eb4164f',
  (),
  (),
  (),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct AssistanceDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  381,
  '3471b166fa73e8e5f945e05007ad4ce2e90a15d26b1395630aee6d45ac47c492',
  (),
  (),
  (),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct TemporalEvidenceDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  229,
  '9951ad122ff9f129f819fa7824b964b0e767533f097b790eff3e00b5023daee7',
  (),
  (),
  (),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct DiagnosticExportV1: Codable, Equatable, Sendable {',),
  1,
  1250,
  '12ef763e50d40795b9daeda0f47e5d085aa9a1236b3920fbbf05e1f71a237cc4',
  (),
  (),
  ('&& counters.isValid',
   '&& (metricKit?.isValid ?? true)',
   'RequirementAssuranceSnapshotCanonicalCodecV1.isValid($0)',
   '&& (workPacket?.isValid ?? true)',
   '&& (measurementIntegrity?.isValid ?? true)',
   '&& (privacyTransform?.isValid ?? true)',
   '&& (clientCapability?.isValid ?? true)',
   '&& (recoverabilityVerification?.isValid ?? true)',
   '&& (fieldReference?.isValid ?? true)',
   '&& (accessibleDocument?.isValid ?? true)',
   '&& (schedule?.isValid ?? true)',
   '&& (advancedSchedule?.isValid ?? true)',
   '&& (plan?.isValid ?? true)',
   '&& (placementPose?.isValid ?? true)',
   '&& (assistance?.isValid ?? true)',
   '&& (temporalEvidence?.isValid ?? true)'),
  ('Complete export aggregate validity joins every metadata validator; no true fallback',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func prepare() async throws -> PreparedDiagnosticExportV1 {',
  ('struct DiagnosticExportService {',),
  1,
  1484,
  '9e43645b74b68ba4820ee023505c43363e9c22967ffbe60f56926c45bd636f22',
  (),
  (),
  ('guard value.isValid else {',
   'throw DiagnosticExportError.invalidValue',
   'let canonicalData = try DiagnosticExportCanonicalEncoderV1.encode(value)',
   'try IntegrationProjectionDiagnosticExclusionV1.validate(canonicalData)',
   'try C34SceneNavigationDiagnosticExclusionV1.validate(canonicalData)',
   'canonicalData',
   'return PreparedDiagnosticExportV1(value: value, canonicalData: canonicalData)'),
  ('Complete export/support prepare rejects invalid metadata/canonical bytes and visibly normalizes '
   'invalidSource',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func prepare(\n'
  '        accessGate: any AppAccessGatePortV1\n'
  '    ) async throws -> PreparedDiagnosticExportV1 {',
  ('struct DiagnosticExportService {',),
  1,
  231,
  '56a662307a402cc3d32c87e8effd59d1ff09e7cd1e780c72401718d2a063943f',
  (),
  (),
  (),
  ('Complete export/support prepare rejects invalid metadata/canonical bytes and visibly normalizes '
   'invalidSource',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    static func encode(_ value: DiagnosticExportV1) throws -> Data {',
  ('enum DiagnosticExportCanonicalEncoderV1 {',),
  1,
  3575,
  '5f0adf0885472cb7562c87dd663860bc33c5fc5ea5e00d6c65f59bb29fc46623',
  (),
  (),
  ('guard value.isValid else {', 'throw DiagnosticExportError.invalidValue'),
  ('Complete sole diagnostic encoder rejects invalid metadata',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func prepare(\n'
  '        mode: SupportBundleModeV1,\n'
  '        cancellation: SupportExportCancellationV1 = .never\n'
  '    ) async throws -> SupportExportResultV1 {',
  ('struct SupportBundleBuilderV1: Sendable {',),
  1,
  5356,
  '6f04a2f75a317a92bacace6d77fb18fe3f73d07bb37865f84a634c0fdf2add7e',
  (),
  (),
  ('guard diagnostic.canonicalData.count',
   'throw SupportBundleBuilderFailureV1.sizeLimitExceeded',
   'guard diagnostic.value.isValid,',
   ') == diagnostic.canonicalData else {',
   'throw SupportBundleBuilderFailureV1.invalidSource',
   'diagnostic.canonicalData',
   '} catch let failure as SupportBundleBuilderFailureV1 {',
   'throw failure',
   '} catch {',
   '(.diagnosticSummary, "diagnostic-summary.json", diagnostic.canonicalData)',
   'guard snapshot.counters.isValid else {',
   'guard !overflow, next <= SupportBundleManifestV1.maximumCanonicalBytes else {',
   'guard payload.count <= SupportBundleManifestV1.maximumCanonicalBytes else {',
   'throw SupportBundleBuilderFailureV1.writeFailed'),
  ('Complete export/support prepare rejects invalid metadata/canonical bytes and visibly normalizes '
   'invalidSource',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(\n'
  '        captures: [MeasurementCaptureV1],\n'
  '        series: [MeasurementSeriesV1] = [],\n'
  '        qualityAssessments: [MeasurementQualityAssessmentV1] = [],\n'
  '        calibrationStatuses: [CalibrationStatusV1] = []\n'
  '    ) throws {',
  ('struct MeasurementIntegrityDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1735,
  'df74b454edd372ff39c41f5e315ef40c69f300ebbf55e78dd898a4efccd8d579',
  (),
  (),
  ('guard captures.count <= MeasurementIntegrityLimitsV1.maximumSampleCount,',
   'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct MeasurementIntegrityDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  62,
  'afe88b36273cfa5c673b9fa33fa187586ec9d31adf6c4e64839d9bdec0a0baf8',
  (),
  (('optionalTry', 33, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct MeasurementIntegrityDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  948,
  'dc30735e4cb1d7f183f4e480ed633a5da46427381c718351a7c352e34b742aa4',
  (),
  (),
  ('guard schemaVersion == Self.schemaVersion,', 'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(\n'
  '        approvedProjections: [PrivacyTransformReportProjectionV1] = [],\n'
  '        deniedProjectionStates: [PrivacyProjectionDenialV1] = [],\n'
  '        manifestCount: Int? = nil\n'
  '    ) throws {',
  ('struct PrivacyTransformDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1531,
  '0df7b0a72e59a3c8abc34eea2f433fdfea2e69f7be0424e845bb84cc1e1d9902',
  (),
  (),
  ('guard Set(orderedDenials).count == orderedDenials.count,', 'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct PrivacyTransformDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct PrivacyTransformDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  794,
  'c5591b8f5104595a97f1f1ba4ec56c182245b261ffd771bd143cdcff3a8e6a4b',
  (),
  (),
  ('guard schemaVersion == Self.schemaVersion,', 'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(projection: ClientCapabilityReportProjectionV1) throws {',
  ('struct ClientCapabilityDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  771,
  '3887812d75f0c98d517ce68f5dea6157861ca1060b363a88c7321eaa1eb697d9',
  (),
  (),
  (),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct ClientCapabilityDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct ClientCapabilityDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1240,
  '62bac3e1cf214a616630d37f63059766835fb037070d542e39aec2391f858d1d',
  (),
  (),
  ('guard schemaVersion == Self.schemaVersion,',
   'throw DiagnosticExportError.invalidValue',
   'guard historicExportAllowed == (',
   'guard writeAllowed == (',
   'guard readAllowed == (admission == .readWrite || admission == .readOnly) else {'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(\n'
  '        receipts: [RecoverabilityVerificationReceiptV1] = [],\n'
  '        staging: [RecoverabilityVerificationStagingV1] = []\n'
  '    ) throws {',
  ('struct RecoverabilityVerificationDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  3156,
  '43a5c7994509bcc7d0ae592f4506b209e429e2fe0e3cc63df19c1e0cbfeb2f7e',
  (),
  (),
  ('guard receipts.count <= Self.maximumValues,',
   'throw DiagnosticExportError.invalidValue',
   'guard Set(receiptIDs).count == receiptIDs.count,',
   'quarantinedCount = receipts.filter { $0.disposition == .quarantined }.count'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct RecoverabilityVerificationDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct RecoverabilityVerificationDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  2019,
  'c020a953880ddd58064b53e997fe0ad76035c8f793710112e253aff697bcec6f',
  (),
  (),
  ('+ quarantinedCount + cancelledCount',
   'guard schemaVersion == Self.schemaVersion,',
   '[passedCount, failedCount, unsupportedCount, quarantinedCount, cancelledCount]',
   'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(projections: [FieldReferenceReportProjectionV1]) throws {',
  ('struct FieldReferenceDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1527,
  '4a219ddfd449deda63e9188756b313dfbb3529ea910766e3dcccb6b534ba3429',
  (),
  (),
  ('guard projections.count <= Self.maximumValues else {', 'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct FieldReferenceDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct FieldReferenceDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1325,
  '3bbc47840633dcb3f500a723aef53aa64249ac291e3797aacfb837289bc35b77',
  (),
  (),
  ('guard availabilityCounts.allSatisfy({',
   'throw DiagnosticExportError.invalidValue',
   'guard schemaVersion == Self.schemaVersion,'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(\n'
  '        trees: [AccessibleDocumentSemanticTreeV1] = [],\n'
  '        assessments: [AccessibleDocumentAssessmentReceiptV1] = []\n'
  '    ) throws {',
  ('struct AccessibleDocumentDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  3615,
  '00fad71b04b2bc43460925066b88a2a5058a8ade34cca4b621c7e5fb317620c5',
  (),
  (),
  ('guard trees.count <= Self.maximumValues,',
   'throw DiagnosticExportError.invalidValue',
   'guard Set(treeDigests).count == trees.count else {',
   'guard let tree = treeByDigest[assessment.treeSHA256] else {',
   'guard nodes.count <= Self.maximumValues,'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct AccessibleDocumentDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct AccessibleDocumentDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  2499,
  '2da5629e83bf78b10fe19ced39d27ebb63797a09ccfe8eaf966d3ad2aa769105',
  (),
  (),
  ('guard schemaVersion == Self.schemaVersion,', 'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(\n'
  '        locators: [AssetLocatorV1] = [],\n'
  '        receipts: [LocatorBindingReceiptV1] = []\n'
  '    ) throws {',
  ('struct AssetLocatorDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1220,
  '6f71216c30ac07f47a8dad06085a889711302eefd0534fbcd1200937a3bb085e',
  (),
  (),
  ('guard locators.count <= Self.maximumValues,', 'throw DiagnosticExportError.invalidValue', '} catch {'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct AssetLocatorDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct AssetLocatorDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  737,
  '30c97f41086d5c31a1fba43719dc332674d34eab318dc5578c01ed3959369ab4',
  (),
  (),
  ('guard schemaVersion == Self.schemaVersion,', 'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(\n'
  '        definitions: [ScheduleDefinitionReleaseV1] = [],\n'
  '        history: [OccurrenceHistoryEventV1] = [],\n'
  '        dueProjectionEntryCount: Int = 0,\n'
  '        reminderProjectionEntryCount: Int = 0\n'
  '    ) throws {',
  ('struct ScheduleDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1413,
  '757c23c9e5203f0e2139a831c85974668de391149097f532a59dc578afc05072',
  (),
  (),
  ('guard definitions.count <= Self.maximumValues,', 'throw DiagnosticExportError.invalidValue', '} catch {'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct ScheduleDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct ScheduleDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  697,
  'ed3937b93c7d63b45a8d168f14691dbd873477437e79b08b738c28c150d544a5',
  (),
  (),
  ('guard schemaVersion == Self.schemaVersion,', 'throw DiagnosticExportError.invalidValue'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    init(calendars: [ExceptionCalendarReleaseV1] = [],\n'
  '         overrideEvents: [ScheduleOverrideEventV1] = [],\n'
  '         occurrences: [ScheduleChangeOccurrenceInputV1] = [],\n'
  '         previews: [ScheduleChangePreviewV1] = [],\n'
  '         receipts: [ScheduleChangeReceiptV1] = []) throws {',
  ('struct AdvancedScheduleDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  1932,
  '8d59030ed26d579eefdcdd0a3093f42a4db5ac8ff23efb00e06da3909241c71e',
  (),
  (),
  ('guard [calendars.count, overrideEvents.count, occurrences.count,',
   'throw DiagnosticExportError.invalidValue',
   'guard let preview = previews.first(where: { $0.previewSHA256 == receipt.previewSHA256 }) else {',
   '} catch { throw DiagnosticExportError.invalidValue }',
   'activeOverrideCount = try ScheduleOverridePrecedenceV1.activeEvents(overrideEvents).count',
   '} catch {'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    var isValid: Bool {',
  ('struct AdvancedScheduleDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  50,
  'f8bc240f522e4b008442927457fad973245dc824b475d3c2cbee467c2a99b8f8',
  (),
  (('optionalTry', 25, ()),),
  (),
  ('Exact typed metadata validate-to-false wrapper; complete validate and checked rejectors; graph-invalid '
   'failure normalizes to existing invalidValue.',
   'Complete export aggregate validity joins every metadata validator; no true fallback')),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift',
  '    func validate() throws {',
  ('struct AdvancedScheduleDiagnosticMetadataV1: Codable, Equatable, Sendable {',),
  1,
  744,
  '22ca47d80c635ac0852d51d3c089ebd36cfab80699261e70c232295f8b5a69d3',
  (),
  (),
  ('guard schemaVersion == Self.schemaVersion,',
   '[calendarReleaseCount, overrideEventCount, activeOverrideCount,',
   'activeOverrideCount <= overrideEventCount,',
   'digestsExcluded else { throw DiagnosticExportError.invalidValue }'),
  ('Complete corresponding metadata validation/checked initializer, not a validate-name whitelist',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift',
  'enum OperationalLogRegistryV1 {',
  (),
  0,
  2065,
  '2e597aa6f1e1b5341ec5231d89a4275b20fe3abb18e57cf285f813a7ca641f07',
  (),
  (),
  ('guard matches.count == 1, let value = matches.first else {',
   'throw OperationalDiagnosticsValidationFailureV1.registryMismatch',
   'guard descriptors.count == OperationalLogCodeV1.allCases.count,'),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift',
  'enum OSLogEmissionPolicyV1 {',
  (),
  0,
  262,
  'c17e47003b18a93f3b6561bed3bba6446c95f1177d6e4a67e6386bf144d00b9e',
  (),
  (),
  (),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift',
  'struct DiagnosticsLogger: Sendable {',
  (),
  0,
  4315,
  '2d576d0d480a2136e00b4a7bfb3894aa2d8b6189d050538c55a445c8574861d7',
  (),
  (),
  ('guard category == .wrongPassphraseOrDamage else { return }',),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private static func category(_ error: Error) -> String {',
  ('enum OriginalEraseScratchFirstErrorDiagnosticV1 {',),
  1,
  2400,
  '272e26f67d8d99e40670ac4215232f6666629acab312e14ca6fde89a00835999',
  ('if DEBUG',),
  (),
  (),
  ('Closed scratch/erase/policy/generation error categories, no descriptions',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    static func emitSourceCutMembers(stage: String, count: Int) {',
  ('enum OriginalEraseScratchFirstErrorDiagnosticV1 {',),
  1,
  326,
  '7bb054f29d4f48c06e5a1bc28514e83dec1b4a96d6abe593a2644aa60eb58ad6',
  ('if DEBUG',),
  (('optionalTry', 256, ('if DEBUG',)),),
  ('defer { errno = saved }',),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    static func emitSourceCutError(stage: String, error: Error,\n'
  '        started: UInt64, stageStarted: UInt64) {',
  ('enum OriginalEraseScratchFirstErrorDiagnosticV1 {',),
  1,
  648,
  '37fee85be8345627717f563b75774da03376f20142807cd9b053d5b2ea67b19a',
  ('if DEBUG',),
  (('optionalTry', 578, ('if DEBUG',)),),
  ('defer { errno = saved }',),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private func makeSnapshot() -> OwnedStorageSnapshotV1 {',
  ('final class OwnedStorageLedgerV1: WorkspaceStorageAdmissionPortV1, @unchecked Sendable {',),
  1,
  437,
  'f49e21e4a75f9424cf351a6596226486d5bba55fd0b0d0d5d135a00aab18c632',
  (),
  (('optionalTry', 84, ()),),
  (),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'private func reportOriginalNotificationRootDiagnostic(_ stage: String,\n    syscallErrno: Int32? = nil) {',
  (),
  0,
  323,
  'e09244c354a0ac87da4b7d74c7b6c9b25a7e373dd9b3e6c41c7025d52bae0ea7',
  ('if DEBUG',),
  (('print', 139, ('if DEBUG',)), ('print', 249, ('if DEBUG',))),
  (),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',
   'Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure')),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    init(operationsURL: URL, rootName: String,\n'
  '        originalEraseNotificationDiagnostic: Bool = false,\n'
  '        retainedOriginalEraseIO: EraseAbortCheckedSnapshotIOV1? = nil) throws {',
  ('private final class PinnedScratchRootV1: @unchecked Sendable {',),
  1,
  4344,
  '519a8b77273b65c2528d1d489b09e01ff9c21edd780cec25d0e89c08a9c2b8e3',
  (),
  (),
  ('guard operationsDescriptor >= 0 else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard operationsStatResult == 0,',
   'let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)',
   'ScratchUncertainCloseQuarantineV1.shared.complete(attempt)',
   'retainedOriginalEraseIO?.retainUncertainDescriptor(operationsDescriptor)',
   'guard rootDescriptor >= 0 else {',
   'guard rootStatResult == 0,',
   'let rootAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(rootDescriptor)',
   'ScratchUncertainCloseQuarantineV1.shared.complete(rootAttempt)',
   'retainedOriginalEraseIO?.retainUncertainDescriptor(rootDescriptor)',
   'let operationsAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)',
   'ScratchUncertainCloseQuarantineV1.shared.complete(operationsAttempt)'),
  ('Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    func closeCheckedForExclusiveOriginalEraseRead(\n'
  '        verifyBeforeClose: Bool = true\n'
  '    ) throws {',
  ('private final class PinnedScratchRootV1: @unchecked Sendable {',),
  1,
  1142,
  '330cdc2b367f387354f055bbf5cd5ba9acc54db26edf5f3c056cdcf3e642674a',
  (),
  (),
  ('guard originalCleanupBorrowCheck == nil else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'rootCloseAttempted = true',
   'let rootAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(root)',
   'ScratchUncertainCloseQuarantineV1.shared.complete(rootAttempt)',
   'operationsCloseAttempted = true',
   'let operationsAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(operations)',
   'ScratchUncertainCloseQuarantineV1.shared.complete(operationsAttempt)',
   'if failed { throw ScratchDataLeaseStoreFailureV1.invalidRoot }'),
  ('Checked exclusive close quarantines uncertain descriptor and rethrows',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    init(applicationSupportURL: URL, preferences: PreferencesAdapterV1,\n'
  '         failurePoint: AppLockNotificationControlFailurePointV1 = .none,\n'
  '         mustExistForOriginalErase: Bool = false,\n'
  '         originalFirstNotificationPresence:\n'
  '            OriginalEraseNotificationFirstPresenceV1? = nil,\n'
  '         retainedOriginalEraseIO: EraseAbortCheckedSnapshotIOV1? = nil) throws {',
  ('final class AppLockNotificationControlStoreV1: @unchecked Sendable {',),
  1,
  1630,
  '6ce08d0726c0053bf4621d218ae75fce8fb1db38bfcab2481f4c2c72dca12927',
  (),
  (('print', 1099, ('if DEBUG',)),),
  ('guard retainedOriginalEraseIO == nil || mustExistForOriginalErase else {',
   'throw AppAccessContractFailureV1.configurationUnknown',
   'guard applicationSupportURL.isFileURL else { throw AppAccessContractFailureV1.configurationUnknown }'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    func requireNotificationSchedulingTerminal(_ owner: NotificationSchedulingPublicationOwner,\n'
  '        verifiedPresent: Bool) throws {',
  ('final class AppLockNotificationControlStoreV1: @unchecked Sendable {',),
  1,
  1600,
  'a1f5592dd43819337e203c8eae54c1430ee24cd5da0aff0a9897d2b7655f65e7',
  (),
  (('optionalTry', 1500, ()),),
  ('guard try schedulingState(owner) == (verifiedPresent ? owner.t : owner.f),',
   'throw AppAccessContractFailureV1.notificationReconciliationRequired',
   'guard file >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }',
   'var closeAttempted = false',
   'guard Darwin.fstat(file, &held) == 0,',
   'throw AppAccessContractFailureV1.effectMismatch',
   'guard Darwin.fsync(file) == 0,',
   'closeAttempted = true',
   '} catch {',
   'if !closeAttempted { try? schedulingClose(file, owner: owner) }',
   'throw error'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private func schedulingClose(_ file: Int32,\n'
  '        owner: NotificationSchedulingPublicationOwner?) throws {',
  ('final class AppLockNotificationControlStoreV1: @unchecked Sendable {',),
  1,
  436,
  '943855f94c5835259a35ae9e9ac2ec094f2a1665429129f4e2088356eddd09f1',
  (),
  (),
  ('let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(file)',
   'guard Darwin.close(file) == 0 else {',
   'owner?.uncertainClose = true',
   'throw AppAccessContractFailureV1.notificationReconciliationRequired',
   'ScratchUncertainCloseQuarantineV1.shared.complete(attempt)'),
  ('Checked scheduling close quarantines uncertain descriptor and rethrows',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private func schedulingReadCanonical(_ owner: NotificationSchedulingPublicationOwner? = nil)\n'
  '        throws -> (Data, stat)? {',
  ('final class AppLockNotificationControlStoreV1: @unchecked Sendable {',),
  1,
  2404,
  '54fff7239cc8136b0ddbfca70c7556df9350193f23635005b03c8ed4eba19584',
  (),
  (('optionalTry', 2322, ()),),
  ('guard let named = try schedulingRawInformation(Self.mappingName) else { return nil }',
   'guard named.st_size > 0 else { throw AppAccessContractFailureV1.effectMismatch }',
   'guard file >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }',
   'var closeAttempted = false',
   'guard Darwin.fstat(file, &held) == 0, Self.sameFile(named, held) else {',
   'throw AppAccessContractFailureV1.effectMismatch',
   'guard Darwin.fstat(file, &after) == 0, Self.sameFile(held, after),',
   'Self.sameFile(held, final) else { throw AppAccessContractFailureV1.effectMismatch }',
   'retainUncertainDescriptor: { descriptor in',
   'owner?.uncertainClose = true',
   '_ = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)',
   'guard observed.device == UInt64(held.st_dev), observed.inode == UInt64(held.st_ino),',
   'throw AppAccessContractFailureV1.configurationUnknown',
   'Self.sameFile(held, final), owner?.uncertainClose != true else {',
   'closeAttempted = true',
   '} catch {',
   'if !closeAttempted { try? schedulingClose(file, owner: owner) }',
   'throw error'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private static func openRoot(_ supportURL: URL,\n'
  '        mustExistForOriginalErase: Bool = false,\n'
  '        originalErasePolicyIO: EraseAbortCheckedSnapshotIOV1? = nil) throws\n'
  '        -> (support: Int32, device: UInt64, inode: UInt64, authority: PinnedScratchRootV1) {',
  ('final class AppLockNotificationControlStoreV1: @unchecked Sendable {',),
  1,
  7541,
  'b4ce3bb3c496824e5e518002fa772011bdd249a11a3e634379441ca44a2a19cc',
  (),
  (('optionalTry', 3859, ()),),
  ('guard support >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }',
   'let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(support)',
   'ScratchUncertainCloseQuarantineV1.shared.complete(attempt)',
   'originalErasePolicyIO.retainUncertainDescriptor(support)',
   'guard Darwin.fstat(support, &information) == 0,',
   'throw AppAccessContractFailureV1.configurationUnknown',
   'guard Darwin.mkdirat(support, operationsName, 0o700) == 0',
   'guard operations >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }',
   'var operationsCloseAttempted = false',
   'if !operationsCloseAttempted {',
   'let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(operations)',
   'originalErasePolicyIO.retainUncertainDescriptor(operations)',
   'guard Darwin.fstat(operations, &operationsInfo) == 0,',
   'guard created || errno == EEXIST else {',
   'guard UInt64(operationsInfo.st_dev) == pinned.operationsDevice,',
   'at: root, retainUncertainDescriptor: {',
   'retainOriginalEraseUncertainPolicyDescriptor(',
   'guard observed.device == pinned.rootDevice,',
   'guard sameOriginalEraseRootFact(firstRoot, finalRoot) else {',
   'guard Darwin.fsync(pinned.rootDescriptor) == 0,',
   'operationsCloseAttempted = true',
   'let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(',
   'guard Darwin.close(operations) == 0 else {',
   '} catch {',
   'throw error'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',
   'Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure')),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    fileprivate enum DiagnosticStage: String {',
  ('@MainActor\nfinal class OriginalEraseScratchCleanupAttemptV1 {',),
  1,
  306,
  'e3b7474ba082419558352bb3d3a3a3496592c3a9625a43040369dcdd30b82158',
  ('if DEBUG',),
  (),
  (),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    fileprivate func recordOriginalFailureDiagnostic(_ error: Error) {',
  ('@MainActor\nfinal class OriginalEraseScratchCleanupAttemptV1 {',),
  1,
  390,
  '32fc6a328e15d35135a527c807c752196d063c1c6d5a34b76d63ab6a291c6c4b',
  ('if DEBUG',),
  (),
  ('guard !diagnosticFirstErrorRecorded else { return }',),
  ('Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    fileprivate func closeResource(_ resource: Resource, terminalCleanup: Bool) throws {',
  ('@MainActor\nfinal class OriginalEraseScratchCleanupAttemptV1 {',),
  1,
  4285,
  '2672af65f695c213b7468d8e30ea104d21b1c9e7aa1279f81d78325ec76517da',
  (),
  (),
  ('guard resource.state == .open else { return }',
   'resource.state = .uncertain',
   'retainedIO.retainUncertainDescriptor(resource.descriptor)',
   'guard activeIntent == nil, activeOutcome == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot '
   '}',
   'guard !next.overflow else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }',
   'guard result == 0 else { poison(); throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   '} catch {',
   'poison()',
   'throw failure',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot'),
  ('Terminal checked resource close; uncertainty retained, no cold numeric fallback',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    func closeCheckedForExclusiveOriginalEraseRead(verifyBeforeClose: Bool = true) throws {',
  ('private enum ScratchStoreAuthorityV1: @unchecked Sendable {',),
  1,
  296,
  '3be302312f324794ceef4df143e41a2b593c631dab9ffceefaa4436f5305aa35',
  (),
  (),
  ('guard case .original(let pin) = self else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',),
  ('Checked exclusive close quarantines uncertain descriptor and rethrows',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor private func coldCleanupDirectoryNames(_ descriptor: Int32,\n'
  '        attempt: OriginalEraseScratchCleanupAttemptV1) throws -> [String] {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  3032,
  '39b2590d8aeff6d768b2a9349dc667fadf82c8bd0433145042c9895d55d0e637',
  (),
  (('optionalTry', 2931, ()),),
  ('guard originalCleanupAttempt === attempt, attempt.coldRanges != nil,',
   'attempt.catalogSession == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {',
   'guard errno == 0, Set(names).count == names.count else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard let tree else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard node.path.hasPrefix(prefix) else { return nil }',
   'guard names.sorted() == expected else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   '} catch {',
   'attempt.poison()',
   'throw failure'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor private func originalCleanupDirectoryNames(_ descriptor: Int32) throws -> [String] {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  3660,
  'e2294a4a571b69b2d374726cbf4c5c8acd4489e0c4950f3336d089e636ff8106',
  (),
  (('optionalTry', 3559, ()),),
  ('guard let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard fd >= 0, let resource = attempt.resources[fd] else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard let directory else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {',
   'guard errno == 0, Set(names).count == names.count else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard let tree else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard node.path.hasPrefix(prefix) else { return nil }',
   'guard names.sorted() == expected else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   '} catch {',
   'attempt.poison()',
   'throw failure'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor private func coldRequirePhysicalBytes(_ bytes: Data, named name: String,\n'
  '        directoryDescriptor: Int32, attempt: OriginalEraseScratchCleanupAttemptV1) throws {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  3007,
  '01d559f838c7da0e8fa02c1e11ed12d2a21ce9d7a5f77d3b774ff31d325bb0ba',
  (),
  (('optionalTry', 2906, ()),),
  ('guard attempt.coldRanges != nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard selected.fullFact == Self.originalEraseSourceFullFact(expected),',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard descriptor >= 0, let resource = attempt.resources[descriptor] else {',
   'guard try attempt.observe({ Darwin.fstat(descriptor, &held) }) == 0,',
   'guard count > 0, count <= wanted,',
   'guard try attempt.observe({ Darwin.pread(descriptor, &eof, 1, off_t(offset)) }) == 0,',
   '} catch {',
   'attempt.poison(); try? attempt.closeResource(resource, terminalCleanup: true)',
   'throw failure'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor private func originalCleanupReadRegularFile(named name: String,\n'
  '        directoryDescriptor: Int32, maximumBytes: Int) throws -> Data {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  3146,
  '36636056663593b84b734a93485ba2af3e7fcd2683753b0afdc45c97d6f9c574',
  (),
  (('optionalTry', 3045, ()),),
  ('guard let attempt = originalCleanupAttempt, maximumBytes >= 0 else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard attempt.coldRanges == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard expectedNode.fullFact == Self.originalEraseSourceFullFact(expected),',
   'let expectedSHA = expectedNode.contentSHA256 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard expected.st_size <= Int64(maximumBytes) else { throw '
   'ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }',
   'guard descriptor >= 0, let resource = attempt.resources[descriptor] else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard try attempt.observe({ Darwin.fstat(descriptor, &pinned) }) == 0,',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard read > 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard try attempt.observe({ Darwin.fstat(descriptor, &after) }) == 0,',
   'guard try CompatibilityCanonicalV1.sha256(bytes) == expectedSHA else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   '} catch {',
   'attempt.poison(); try? attempt.closeResource(resource, terminalCleanup: true)',
   'throw failure'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor private func captureOriginalCleanupCanonicalSources() throws {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  5016,
  'cf622a78a89f73b356c001043a1729671b5524c3efa4ef0d5986bc41301bcbeb',
  (),
  (('optionalTry', 2411, ()),),
  ('guard let attempt = originalCleanupAttempt, !attempt.sourcesCaptured else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard parts.count == 2, parts[1] == Self.metadataName else { continue }',
   'guard Self.isLeaseDirectoryName(directoryName) || Self.isDeletionTombstone(directoryName) else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidLease',
   'guard let resource = attempt.resources[descriptor] else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,',
   'try canonicalData(lease) == bytes else { throw ScratchDataLeaseStoreFailureV1.invalidLease }',
   '} catch {',
   'attempt.poison(); try? attempt.closeResource(resource, terminalCleanup: true)',
   'throw failure',
   'guard fields.count == 11, let mode = UInt32(fields[2]), mode & UInt32(S_IFMT) == UInt32(S_IFDIR),',
   'guard !(attempt.initialImage.scratch?.nodes.contains(where: {',
   '}) ?? true) else { throw ScratchDataLeaseStoreFailureV1.invalidLease }',
   'guard let pinned = ingressControlAuthority else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard !node.path.contains("/") else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private init(verifiedExistingTemporalRootAt applicationSupportURL: URL,\n'
  '                 clock: @escaping Clock,\n'
  '                 capacityProvider: @escaping StoragePreflightService.CapacityProvider = { _ in nil },\n'
  '                 checkedClose: Bool = false) throws {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  2125,
  'd260f2be3398e761e0c98e281ad05528cb5fe07e80ed61997f8d19d14e45703a',
  (),
  (('optionalTry', 2003, ()),),
  ('retainUncertainDescriptor: {',
   '_ = ScratchUncertainCloseQuarantineV1.shared.begin($0)',
   '} catch {',
   'throw error'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor\n'
  '    private func checkedOriginalEraseSourceCut(\n'
  '        expected: OriginalEraseScratchImageV1, allowingSettledRootAdvance: Bool = false\n'
  '    ) throws -> OriginalEraseExclusiveSourceCutV1 {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  10037,
  'd6ae7e05b4474e21a989e9dce1695f85678f23f0a087fb67a3a0aab26078ad15',
  (),
  (),
  ('guard exclusiveNoRepairRead, let io = originalEraseSourceReceiptIO else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard Darwin.fstat(operationsFD, &operations) == 0,',
   'guard operationsNames.contains(Self.rootName),',
   'guard image == repeated else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'else { guard image == expected else { throw ScratchDataLeaseStoreFailureV1.invalidRoot } }',
   'guard Darwin.fstat(operationsFD, &operationsAfter) == 0,',
   '} catch {',
   'throw error'),
  ('Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '        func observedScratchNames(_ names: [String], stage: String) -> [String] {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  2,
  243,
  '776f2b4daa582ca1768640ed24c360900f16ff165b487fb6a94e3ffeb8e3e618',
  ('if DEBUG',),
  (),
  (),
  ('Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private func acquireScratchLeaseSynchronously(\n'
  '        _ request: ScratchDataLeaseRequestV1,\n'
  '        recoverExisting: Bool = true,\n'
  '        originalNoRepairImage: OriginalEraseScratchImageV1? = nil\n'
  '    ) throws -> ScratchDataLeaseV1 {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  6129,
  'a354c9918fb31485fbec9ae1f92d094707ed0168892bf0ab41ba70f9eddcc0be',
  (),
  (('optionalTry', 5642, ()), ('optionalTry', 5874, ()), ('optionalTry', 6012, ())),
  ('guard request.createdAt <= current, current < request.expiresAt else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidLease',
   'guard !recoverExisting, exclusiveNoRepairRead,',
   'guard active.isEmpty,',
   'throw ScratchDataLeaseStoreFailureV1.leaseCollision',
   'guard existing.request == request else {',
   '} catch StoragePreflightError.insufficientCapacity {',
   'throw ScratchDataLeaseStoreFailureV1.insufficientCapacity',
   '} catch StoragePreflightError.capacityUnavailable {',
   '} catch {',
   'guard one == image, two == image else {',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard Darwin.mkdirat((try authority.rootDescriptor), name, 0o700) == 0 else {',
   'var closeAttempted = false',
   'if leaseDescriptor >= 0 && !closeAttempted {',
   'let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(leaseDescriptor)',
   'ScratchUncertainCloseQuarantineV1.shared.complete(attempt)',
   'let metadata = try canonicalData(lease)',
   'closeAttempted = true',
   'let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(owned)',
   'guard Darwin.close(owned) == 0 else {',
   '} catch let failure as ProtectedFilePolicyError',
   'throw ScratchDataLeaseStoreFailureV1.protectedDataUnavailable',
   '} catch let failure as ScratchDataLeaseStoreFailureV1 {',
   'throw failure'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor private func publishOriginalCleanupDurably(_ data: Data,\n'
  '        named name: String, directoryDescriptor: Int32, directoryURL: URL,\n'
  '        finalURL: URL, leaseName: String?, atomicExclusiveRename: Bool,\n'
  '        directoryAuthorityCheck: (() throws -> Void)?) throws {',
  ('final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {',),
  1,
  6465,
  '3d2f42e5266063b71625f2d984161dce428d0d403366c0e8d58b7972f6a14779',
  (),
  (('optionalTry', 6364, ()),),
  ('guard let attempt = originalCleanupAttempt,',
   'throw ScratchDataLeaseStoreFailureV1.invalidRoot',
   'guard try readRegularFile(named: name, directoryDescriptor: directoryDescriptor,',
   'maximumBytes: data.count) == data else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard try attempt.requireRetainedCanonicalPublication(path: finalPath, bytes: data) else {',
   'guard let intent = attempt.activeIntent else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard opened >= 0, let resource = attempt.resources[Int32(opened)] else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard count > 0, count <= Int64(requested) else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard try originalCleanupSync(descriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard result == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }',
   'else { guard try originalCleanupUnlink(directoryDescriptor, temporaryName, 0) == 0 else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot } }',
   'guard try originalCleanupSync(directoryDescriptor) == 0 else { throw '
   'ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'guard try readRegularFile(named: name, directoryDescriptor: directoryDescriptor, maximumBytes: '
   'data.count) == data else {',
   '} catch {',
   'attempt.poison(); try? attempt.closeResource(resource, terminalCleanup: true)',
   'throw failure'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private enum ColdOwnedIDsReserveDiagnosticStageV1: String {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',),
  1,
  1769,
  '4afb3d11bbe764cf0d301da2f20a5cac743534980f8d51986d23b7cebcd6ad95',
  ('if DEBUG',),
  (),
  (),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    @MainActor private final class ColdOwnedIDsReserveDiagnosticContextV1 {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',),
  1,
  1569,
  'd363852138b52d5875ec6c8767e3a72ba81fdda37077cd26a438a6c101af1891',
  ('if DEBUG',),
  (),
  ('func isBound(control: EraseSchema2ColdNotificationControlV1,',
   'let savedErrno = errno',
   'defer { errno = savedErrno }'),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '        func isBound(control: EraseSchema2ColdNotificationControlV1,\n'
  '                     operation: EraseColdPreparationOperationV1,\n'
  '                     operationID: UUID) -> Bool {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',
   '    @MainActor private final class ColdOwnedIDsReserveDiagnosticContextV1 {'),
  2,
  369,
  '0c41eaa7e379cc111c94ac549424d315c823275a56a72447be791020e1965b41',
  ('if DEBUG',),
  (),
  (),
  ('Exact actual control/operation/operationID association',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '        func report(_ error: Error) {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',
   '    @MainActor private final class ColdOwnedIDsReserveDiagnosticContextV1 {'),
  2,
  573,
  '22a00c1c102afac89d1175a488a5fae90c274f202652ae559635f476d989dc7e',
  ('if DEBUG',),
  (('optionalTry', 499, ('if DEBUG',)),),
  ('let savedErrno = errno', 'defer { errno = savedErrno }'),
  ('Checked sum overflow; original cleanup; explicit uncertain-close quarantine/poison and original error '
   'rethrow; errno-preserving DEBUG enum/stage or runtime error TYPE.',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private func advanceColdOwnedIDsReserveDiagnostic(\n'
  '        _ stage: ColdOwnedIDsReserveDiagnosticStageV1\n'
  '    ) {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',),
  1,
  339,
  'b56879caf935fe3da6b9eef6183c422483c0b5ca87d77767b27313e38db856fc',
  ('if DEBUG',),
  (),
  ('guard let current = coldOwnedIDsReserveDiagnostic,',
   'current.isBound(control: self, operation: operation,'),
  ('Only same actual control/operation context can advance diagnostic stage',
   'Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure')),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private func withColdOwnedIDsReserveDiagnostic<Value>(\n'
  '        operationID: UUID, _ body: () throws -> Value\n'
  '    ) throws -> Value {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',),
  1,
  701,
  'd2fde77e019646d63a33d2f12f843fef31f9688056330bb46ea6377c96d14273',
  ('if DEBUG',),
  (),
  ('} catch {', 'if current.isBound(control: self, operation: operation,', 'throw error'),
  ('Scoped DEBUG context restore and original-error rethrow',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    private func ensureRoot() throws {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',),
  1,
  4668,
  '73086896115e82750076cf54cdd226db46a2185b740f16225ba0abc20176bfd3',
  (),
  (),
  ('guard created.source === source,',
   'throw AppAccessContractFailureV1.configurationUnknown',
   'guard settled.source === source,',
   'guard !rootIdentityValue.isEmpty,',
   'retainUncertainDescriptor: { value in',
   'self.uncertainPolicyDescriptors.append(value)',
   'guard let fact = cut.rootFact,'),
  ('Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    func reserveSchema2ColdOwnedIDs(\n'
  '        operationID: UUID\n'
  '    ) throws -> NotificationEraseOwnedIDsProvenanceV1 {',
  ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
   '    Schema2ColdNotificationEraseControlV1 {',),
  1,
  22691,
  'b7b70571366301a14c1309b6ce0ae373e2d4f5361673d53ad6692dc92c863984',
  (),
  (),
  ('guard operationID == source.eraseID else {',
   'throw AppAccessContractFailureV1.effectMismatch',
   'guard cut.leafBytes[ownedName] == nil,',
   'throw AppAccessContractFailureV1',
   'guard cut.leafBytes[ownedName] != nil,',
   'guard try checkedRead.cut() == cut else {',
   'throw AppAccessContractFailureV1.configurationUnknown',
   'guard mapping?.entries.allSatisfy({ $0.admissionID == nil })',
   'guard cut.leafBytes[',
   'guard current.operationID == operationID,',
   'guard prefix.count <= expected.count,',
   'guard !(source.names.contains('),
  ('Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    fileprivate func postCloseSourceControlsReadbackForTesting(\n'
  '        authority: StoreRestoreGenerationAuthority, pointerData: Data,\n'
  '        foreignOwner: ErasedRegistryRetirementProofV1?\n'
  '    ) throws -> ErasePostCloseSourceControlsReadbackV1 {',
  ('@MainActor\nfinal class ErasedRegistryRetirementProofV1 {',),
  1,
  2753,
  '5489c9b8dc14b4d65c976362ae9659377262e49d78a88816f763776d54e250bb',
  ('if DEBUG',),
  (('print', 753, ('if DEBUG',)), ('print', 1161, ('if DEBUG',))),
  ('guard phase == .manifestPreserved, let attempt = manifestAttempt,',
   'throw EraseAllServiceError.invalidAuthority',
   '} catch StoreGenerationFailure.dataPointerInvalid {',
   'guard foreignOwner !== self, foreignOwner.binding != binding,',
   '} catch StoreMigrationFailure.invalidIdentity {'),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '        private func reportSourceDifference(\n'
  '            expected: EraseCompletedAbortSourceBytesV1,\n'
  '            observed: EraseCompletedAbortSourceBytesV1\n'
  '        ) {',
  ('@MainActor\nfinal class EraseAllService {', '    private final class CompletedAbortFrame {'),
  2,
  3842,
  'b36aef09352e48604515db331beb7902fe834c4fd861dfc3fc8d35f6dc5a17db',
  ('if DEBUG',),
  (('optionalTry', 2680, ('if DEBUG',)),),
  ('guard lhs.count == 9, rhs.count == 9 else {',),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    private static func preIntentFailureCaseForTesting(_ error: Error) -> String {',
  ('@MainActor\nfinal class EraseAllService {',),
  1,
  1311,
  '23b5bb3fc080ee07232e5fc782616890a37625df5a6bbe50b2ee673ede48bf8f',
  ('if DEBUG',),
  (),
  ('case .uncertainOwner: return "registry.uncertain-owner"',),
  ('Closed typed pre-intent failure labels',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    static func reportPreIntentRefusalForTesting(\n'
  '        site: PreIntentRefusalSiteForTesting, error: Error\n'
  '    ) {',
  ('@MainActor\nfinal class EraseAllService {',),
  1,
  238,
  '24d99f957d051b373148c110e5bf2923f4f79a70d3ed7b500154f1ecec28c38b',
  ('if DEBUG',),
  (('print', 125, ('if DEBUG',)),),
  (),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    private func reportSchema2ColdPForwardFailure(_ error: Error) {',
  ('@MainActor\nfinal class EraseAllService {',),
  1,
  687,
  'fab186d9f41c927e67793cd0836219fcfbd5d0c899d70a1ec90f1f26f933422d',
  ('if DEBUG',),
  (('print', 593, ('if DEBUG',)),),
  (),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    private func originalScratchLoanDiagnosticError(\n'
  '        _ error: Error\n'
  '    ) -> (type: String, category: String) {',
  ('@MainActor\nfinal class EraseAllService {',),
  1,
  6879,
  'c71b60624290f04cfab0047a7967652979373a250b0ec70c16e3a12798d91308',
  ('if DEBUG',),
  (),
  ('case .uncertainOwner: category = "uncertain-owner"',),
  ('Typed closed error categories and bounded runtime TYPE validation, no value description',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    private func reportOriginalScratchLoanFailure(\n'
  '        _ error: Error,\n'
  '        boundary: OriginalScratchLoanDiagnosticBoundary,\n'
  '        operation: EraseRouterOperationV1\n'
  '    ) {',
  ('@MainActor\nfinal class EraseAllService {',),
  1,
  588,
  '79399ad2f1fb4f4299be4f3301352ded0e37fa400442f5c8ff49480a3627a271',
  ('if DEBUG',),
  (('print', 369, ('if DEBUG',)),),
  (),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    private func traceEraseOriginalFailure(_ error: Error) {',
  ('@MainActor\nfinal class EraseAllService {',),
  1,
  2354,
  'd8283f444040f86412c88c60179986516f671805fb33f011df8d2edda7091eab',
  (),
  (('print', 1271, ('if DEBUG',)), ('print', 2043, ('if DEBUG',))),
  ('guard let diagnostic = erasePhaseDiagnosticForTesting else { return }',),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    private func erase(\n'
  '        confirmation: String,\n'
  '        coordinator: StoreSessionCoordinator,\n'
  '        diagnosticsStore: DiagnosticsStore,\n'
  '        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,\n'
  '        operation: EraseRouterOperationV1,\n'
  '        lifecycleRoute: EraseAllLifecycleRouteV1\n'
  '    ) async throws -> EraseAllOutcome {',
  ('@MainActor\nfinal class EraseAllService {',),
  1,
  42366,
  '21debac24c504b3ca4c9f19462511a5b24f0fc041387dac041752e1734239f6f',
  (),
  (('optionalTry', 8722, ('if DEBUG',)),
   ('optionalTry', 12510, ('if DEBUG',)),
   ('print', 37346, ('if DEBUG',))),
  ('guard !originalEraseFrameActive, !postRetiredServiceAbandoned,',
   'throw EraseAllServiceError.invalidAuthority',
   'guard confirmation == Self.requiredConfirmation else {',
   'throw EraseAllServiceError.invalidConfirmation',
   'guard !coordinator.modelContext.hasChanges else {',
   'throw EraseAllServiceError.contextHasChanges',
   'guard sceneNavigationStatePort == nil,',
   'guard let physicalOwner = discovery',
   'guard discoveryAfterActorHop == discoveryBeforeFirstAwait else {',
   'guard !reportedFirstSourceStage else { return }',
   'guard let originalSourceTreeForStages else {',
   'guard observed == originalSourceTreeForStages else {',
   '} catch {',
   'guard newGenerationID != eraseID,',
   'traceErasePhase("authority.failure.line.\\(#line)"); throw EraseAllServiceError.invalidAuthority',
   'guard let originalC05TransientWitness else {',
   'guard try await operation.requireOriginalC05ObservationFence(',
   'throw originalFailure',
   'guard try store.load() == nil,',
   'throw EraseAllServiceError.recoveryRequired',
   'guard afterParentRemoval.directories.isEmpty,',
   'guard try sourceLedgerFactory',
   'guard created.ledgerProof == expectedEmptyLedger,',
   'guard EraseIntentCodecV1.valid(intent) else {',
   'guard let intentStore else {',
   'guard coordinator.generationID == session.generationID,',
   'guard expected != nil else {',
   'guard let originalDiscovery = privateSystemDiscoveryIndex',
   'else { throw EraseAllServiceError.invalidAuthority }',
   'print("V23_ERASE_PREINTENT_REFUSAL_V1 site=service.pre-intent-catch '
   'last-fixed-phase=\\(eraseFixedPhaseForTesting) actual-throw-site=unattributed '
   'case=\\(Self.preIntentFailureCaseForTesting(error))")',
   'guard let frozenIntent,',
   'guard preparation == frozenPreparation',
   'throw error'),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    func validateOriginalRecoverySourceAcrossAdmission(\n'
  '        coordinator: StoreSessionCoordinator,\n'
  '        operation: EraseRouterOperationV1\n'
  '    ) async throws -> OriginalRecoveryValidatedSourceV1? {',
  ('private extension EraseAllService {',),
  1,
  11146,
  '15f3a4a06ebcf4c0511d18e88009614974c7cb3045b2f6df410fa0dfe6c4cc97',
  (),
  (('optionalTry', 4053, ()), ('optionalTry', 6963, ()), ('optionalTry', 11012, ())),
  ('catch { first.poisonOnUncertainScratch(); throw error }',
   'return nil',
   'guard let intent = observed.intent,',
   'first.poisonOnUncertainScratch()',
   'throw EraseAllServiceError.invalidAuthority',
   'guard intent.phase == .emptyGenerationPrepared else {',
   'guard observed.preparation?.matches(intent) == true else {',
   '} catch {',
   'throw error',
   'catch { second.poisonOnUncertainScratch(); throw error }',
   'guard post == observed else {',
   'second.poisonOnUncertainScratch()',
   'guard priorRetired.count == firstPriorRetired.count else {',
   'guard before.image == after.image,',
   'guard namespace == firstNamespace,'),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    init(operation: EraseRouterOperationV1,\n'
  '         authority: StoreRestoreGenerationAuthority,\n'
  '         auxiliary: EraseAuxiliaryAuthority,\n'
  '         oldGenerationID: UUID,\n'
  '         userDefaults: UserDefaults,\n'
  '         defaultsDomainName: String) throws {',
  ('private final class EraseOriginalColdExitFrameV1: @unchecked Sendable {',),
  1,
  2981,
  'f83e793e2c1def06faad124f9b2af64b5abcf7ddecd1b8f6d8c57c0b2fb6da1f',
  ('if DEBUG',),
  (('optionalTry', 2357, ('if DEBUG',)),),
  ('guard try auxiliary.originalEraseSearchStateForTesting() == searchOrigin else {',
   'throw EraseAllServiceError.invalidAuthority',
   'guard try auxiliary.originalEraseNotificationStateForTesting()'),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    func bindCreatedTargetManifest(_ pointer: RestorePointerIdentityV1) throws {',
  ('private final class EraseOriginalColdExitFrameV1: @unchecked Sendable {',),
  1,
  2716,
  '5a824f6ecaf986aa53f7311c2ec7bfc68e01886a1bb69d4f940de8b26de1dd9b',
  ('if DEBUG',),
  (('optionalTry', 939, ('if DEBUG',)),),
  ('guard targetGenerationID == pointer.generationID,',
   'throw EraseAllServiceError.invalidAuthority',
   'guard targetManifest.digest == schemaMigrationOrigin else {',
   '} catch {',
   'throw error'),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    func createZeroDiagnostics(data: Data) throws {',
  ('private final class EraseAuxiliaryAuthority {',),
  1,
  5904,
  '3b63f95bdfd3a8387ca836cc831fbff12fa52cb86c179f3da2afdea854a2f820',
  (),
  (('optionalTry', 3861, ()), ('optionalTry', 5616, ())),
  ('guard Darwin.mkdirat(',
   'throw EraseAllServiceError.invalidAuthority',
   'guard directory >= 0 else {',
   'guard try Self.identity(directory) == expectedDirectory,',
   '} catch {',
   'guard file >= 0 else {',
   'throw error',
   'guard let base = raw.baseAddress else { return }',
   'guard Darwin.fsync(file) == 0 else {',
   'guard Darwin.fsync(directory) == 0,',
   'guard published.identity == expectedFile,'),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  '    func advance() async throws -> Bool {',
  ('@MainActor\nfinal class EraseCleanupAfterRetirementV1 {',),
  1,
  16891,
  '84ee74e7a60a11ee31cce368f145a37c88a4b9a9746669daa3cd941931db3056',
  (),
  (('print', 569, ('if DEBUG',)),
   ('print', 888, ('if DEBUG',)),
   ('print', 1092, ('if DEBUG',)),
   ('print', 1848, ('if DEBUG',)),
   ('print', 2193, ('if DEBUG',)),
   ('print', 2279, ('if DEBUG',)),
   ('print', 2746, ('if DEBUG',)),
   ('print', 3669, ('if DEBUG',)),
   ('print', 4685, ('if DEBUG',)),
   ('print', 5316, ('if DEBUG',)),
   ('print', 5452, ('if DEBUG',)),
   ('print', 5663, ('if DEBUG',)),
   ('print', 5959, ('if DEBUG',)),
   ('print', 8816, ('if DEBUG',)),
   ('print', 9514, ('if DEBUG',)),
   ('print', 9846, ('if DEBUG',)),
   ('print', 10046, ('if DEBUG',)),
   ('print', 10786, ('if DEBUG',)),
   ('print', 12718, ('if DEBUG',)),
   ('print', 13219, ('if DEBUG',)),
   ('print', 13798, ('if DEBUG',)),
   ('print', 14363, ('if DEBUG',)),
   ('print', 14987, ('if DEBUG',)),
   ('print', 15733, ('if DEBUG',)),
   ('print', 16325, ('if DEBUG',)),
   ('print', 16540, ('if DEBUG',))),
  ('guard !running, let retirement else { throw EraseAllServiceError.invalidAuthority }',
   'guard phase != .closeUncertain else { throw EraseAllServiceError.invalidAuthority }',
   'guard phase != .abandonmentPending, phase != .abandoned,',
   'throw EraseAllServiceError.invalidAuthority',
   'guard let actual = try await retirement.validateAndAdvance(factory: factory,',
   'authority: authority, targetReader: targetReader, manifestScope: manifestScope) else { return false }',
   'guard let proof, retirement.ownsProof(proof) else { throw EraseAllServiceError.invalidAuthority }',
   '} catch {',
   'phase = .closeUncertain',
   'throw error',
   'guard try factory.currentGenerationIDForEraseRetirement(authority: authority,',
   'guard retired == intent.generationIDsToDelete || retired.isEmpty else {',
   'guard actual.isSubset(of: allowed), actual.contains(intent.newGenerationID.uuidString.lowercased()) else '
   '{',
   'guard actual == [intent.newGenerationID.uuidString.lowercased()] else {',
   'guard Set(try authority.installedGenerationNames()) == [intent.newGenerationID.uuidString.lowercased()] '
   'else {',
   'guard try factory.retiredGenerationIDsForEraseRetirement(',
   'if authority.eraseRetirementTerminalCloseAttempted {',
   'guard terminalAuthorityClose?.matches(proof: proof,',
   'guard try notificationControl.loadControl() == nil,',
   'throw EraseAllServiceError.recoveryRequired',
   'if closeStarted { phase = .closeUncertain }',
   'guard let originalNotificationTerminalClose else {',
   'guard case .current(let ledger) = try await ratingStore.load(), ledger.attempts.isEmpty,',
   'result.receipt.stateSHA256 == ledger.stateSHA256 else { throw EraseAllServiceError.invalidAuthority }',
   'guard zero.schemaVersion == DeviceOperationalSupportStoreSchemaV2.version,',
   'zero.counters == .zero, zero.health.failures.isEmpty else { throw EraseAllServiceError.invalidAuthority '
   '}',
   'guard feedback.state == .empty, feedback.draft == nil, !feedback.safeCopyAvailable else {',
   'guard await diagnosticsStore.isExactlyZero() else { throw EraseAllServiceError.invalidAuthority }',
   'guard let diagnosticsZero else { throw EraseAllServiceError.invalidAuthority }',
   'guard reservation.subject == binding.subject else { throw EraseAllServiceError.invalidAuthority }'),
  ('Original checked owner retained; DEBUG classification is diagnostic only; abort observations cannot '
   'authorize; cleanup poisons/rethrows; fixed enum/literal stages.',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift',
  '    private static func invalidInventoryFailure(line: UInt = #line) -> '
  'CurrentSyncClassificationCatalogFailureV1 {',
  ('struct CurrentSyncClassificationCatalogV1: Sendable {',),
  1,
  254,
  '8aa593d5d08aa30cce57636bf14a1d53c1b805ac1572d70f060911f932905c21',
  (),
  (('print', 141, ('if DEBUG',)),),
  (),
  ('DEBUG fixed source-line diagnostic returns unchanged invalidInventory.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    @MainActor\n'
  '    func testCompletedEraseReceiptUsesActualIDsAndOnlyPublishesAfterEraseRootRemoval() async throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  3909,
  '05639753854e6aaa656add989d092105176057977996e118841f050c5cc9a094',
  (),
  (('optionalTry', 1841, ()),),
  ('guard let coordinator else { throw V23EraseOperationHarnessV1.Failure.activation }',
   '} catch { activationFailure = error }',
   'if let activationFailure { throw activationFailure }'),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    @MainActor\n    func testAbsentApplicationSupportHasNoEraseAuthority() async throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  1335,
  'af560929360947816ffef84de78290259b8704eaeecf9bcfde8c00d2ac51e9d7',
  (),
  (('optionalTry', 888, ()),),
  (),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    @MainActor\n    func testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState() async throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  14967,
  '9d1d09ebfcc5669062971eb2105288e01bd9b40f2b32288859974bc30b7fccbe',
  (),
  (('print', 199, ()),),
  ('guard case let .ready(fresh, _, _) = owner.router.route else {',
   '(persistedEnvelope["feedbackDraftRecoveryRequired"] as? NSNumber)?.boolValue,',
   'guard case .current(let ratingLedger) = try await reloadedRatingStore.load(),'),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    @MainActor\n    private func verifyCompletedCleanupProbe() throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  2617,
  '887e8addfc4fbe92192fdd93f5a8881cd24c78a57c92121e8d7cfebda16ea5aa',
  (),
  (('optionalTry', 329, ()),),
  (),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    @MainActor\n    func testRetainedLiveContextDefersCleanupUntilColdRecovery() async throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  16322,
  'd6b55218710555b0c866c5df3ae6cdee32ce7adb79f9bb1771aa46866ac4e3dd',
  (),
  (('optionalTry', 6099, ()), ('optionalTry', 7543, ())),
  ('guard let coordinator, let router else {',
   'throw FixtureError.invalid',
   '} catch {',
   'if let activationFailure { throw activationFailure }',
   '.snapshot().canonicalData()',
   '.snapshot().canonicalData(), originalLedger)',
   'guard let pristineCoordinator, let router else {',
   'throw pristineActivationFailure',
   'throw error'),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    @MainActor\n    func testCompletedAbortPhysicalImageRejectsDamagedWALFrame() throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  2328,
  '24f681c30b5402c26d9723eebca484bf9c6eda1ef82b2f5e6941b333d5545253',
  (),
  (('optionalTry', 326, ()),),
  ('guard sqlite3_open_v2(live.path, &connection,',
   'let connection else { throw FixtureError.invalid }',
   'guard sqlite3_exec(connection,',
   'nil, nil, nil) == SQLITE_OK else { throw FixtureError.invalid }',
   'guard modelFD >= 0, walFD >= 0 else {',
   'throw FixtureError.invalid',
   'guard Darwin.pread(walFD, &original, 1, 32 + 24) == 1 else {',
   'guard Darwin.pwrite(walFD, &changed, 1, 32 + 24) == 1,'),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    @MainActor\n    func testCompletedAbortFullIntegrityRejectsFreelistCorruption() throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  2605,
  'eddba89ff5a7750346435751ff3ec667c78876f3072548a628912fdb6505ea48',
  (),
  (('optionalTry', 334, ()),),
  ('guard sqlite3_open_v2(model.path, &connection,',
   'let connection else { throw FixtureError.invalid }',
   'guard sqlite3_exec(connection,',
   'throw FixtureError.invalid',
   'guard sqlite3_close(connection) == SQLITE_OK else {',
   'guard fd >= 0 else { throw FixtureError.invalid }',
   'guard headerRead == header.count else {',
   'guard pageSize >= 512, trunk > 1 else { throw FixtureError.invalid }',
   'guard written == broken.count,',
   'Darwin.fsync(fd) == 0 else { throw FixtureError.invalid }'),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift',
  '    func testPostRetiredOwnerGuardLinkTransitionRetainsOtherTreeFacts() throws {',
  ('final class S6_6EraseRecoveryTests: XCTestCase {',),
  1,
  3818,
  'ef82f4e501e183a0239dc58e1bb0539e00f7e3810ce14684b8e430144b4bf7ad',
  (),
  (('optionalTry', 598, ()),),
  ('let guardName = "owned-guard.lock"',
   'try Data("guard".utf8).write(to: guardURL)',
   'removedChild: "foreign-guard.lock", sourceLinks: beforeLinks))'),
  ('Exact XCTest method/assertion/hostile-fixture cleanup; nil probe fails; genuine checked restore follows '
   'defer; fixed diagnostic phase.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testLegitimatelyWrittenActiveStoreReopensWithoutRepinningItsActivationManifest() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  3829,
  'fcfb9456ed1f2b51b33d20eb4206c7cece8de9e28c896094acc07d1bbb9da3e0',
  (),
  (('optionalTry', 196, ()),),
  ('manifestBytes = try XCTUnwrap(store.loadManifestIfPresent(targetGenerationID: '
   'generationID)).manifest.canonicalData()',
   'XCTAssertEqual(try XCTUnwrap(store.loadManifestIfPresent(targetGenerationID: '
   'generationID)).manifest.canonicalData(), manifestBytes)',
   'guard case .ready(let session) = reopened else { return XCTFail("Already accepted active store must '
   'reopen") }',
   'XCTAssertEqual(try XCTUnwrap(StoreMigrationJournalStoreV1(applicationSupportURL: '
   'root).loadManifestIfPresent(targetGenerationID: generationID)).manifest.canonicalData(), manifestBytes)'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n    func testBootstrapPersistsReleasesAndReopensTheExactGenerationLedger() throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  4164,
  '15fc5dad48a71252af5720aeeecb8ec29af6444ce4d4c8462b52e801c75c6e83',
  (),
  (('optionalTry', 175, ()),),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n    func testInvalidGenerationLedgerFailsClosedWithoutMutationOrNewestGuessing() throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  8957,
  'd19aed8e30009d316891e4b8b6d1e762d105e2d73e8328d39d4d0e462e338610',
  (),
  (('optionalTry', 7054, ()),),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testStoreSessionCoordinatorActivationChangesContextAndMonotonicallyAdvancesToken() throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  2075,
  '0344be59c9ef09e0a31d6e86cef4e863e9f3239cf0f679a455600786c6e12fdf',
  (),
  (('optionalTry', 275, ()), ('optionalTry', 330, ())),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    func testDiagnosticsCreatesExactZeroBytesAndReloadsEveryCounterAndBucket() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  3993,
  'a25988bb7f0d954610e80e7ebb4a016c1a3a9f3cd12dbe3c1059ea9ef2a0e2c7',
  (),
  (('optionalTry', 170, ()), ('optionalTry', 1122, ())),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    func testDiagnosticsCountersAndPurchaseBucketsSaturateAtInt64Max() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  2095,
  'c1a1c91423713c867505e79dd12656a81c1fc3c05ea911688a4ddb37ab113dfc',
  (),
  (('optionalTry', 162, ()),),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    func testMalformedDiagnosticsResetOnlyDiagnosticsAndPreserveDomainSentinels() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  5265,
  '5666d56dd1f1a4fc5ec6c672a9be4d92f8863ab2b83f374f83f53473cdc6fcae',
  (),
  (('optionalTry', 1370, ()), ('optionalTry', 4360, ())),
  ('(persistedEnvelope["feedbackDraftRecoveryRequired"] as? NSNumber)?.boolValue,', '} catch {'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    func testDiagnosticsWriteFailureIsNonGatingAndDoesNotInventAnIncrement() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  838,
  '10e1038ebecd1487fb1d21175bb707e7f2fc033a7aaa4bd4dad53881aea85551',
  (),
  (('optionalTry', 168, ()),),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n    func testStartupUsesTheFrozenOrderBeforeEnablingWrites() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  787,
  'c5014a41f5acff95ee04b44eeb750210ebb3dd5664affeee57f8b0a8df3cbd77',
  (),
  (('optionalTry', 165, ()),),
  ('guard case .ready = router.route else {',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testPendingEraseAndRestoreRootsRouteToTheirExactMaintenanceReasons() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  1553,
  '63c2c7fd47e2755c330dd18d0a8ff5ada09003ca6d1abe6ee34e2694e72bfd77',
  (),
  (('optionalTry', 500, ()),),
  ('guard case let .maintenance(reason) = router.route else {',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testInvalidPointerAndMissingGenerationRouteToExactMaintenanceReasons() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  1744,
  '8ab73e2ebc704fbd6e3b7174ffeaf79a4b38d1e7924575b2adbbec9a831ecf95',
  (),
  (('optionalTry', 716, ()),),
  ('guard case let .maintenance(reason) = router.route else {',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testCorruptReceiptHistoryRoutesToMaintenanceWithoutWriterOrCrash() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  3217,
  'dcab068ced6ec9a51d4b6733ff7e095359f5a1b48f0f3ede0ed86cd261ad731a',
  (),
  (('optionalTry', 180, ()),),
  ('guard case let .maintenance(reason) = router.route else {',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testCorruptReceiptHistoryMaintenanceSupportExportIsReadOnlyAndPrivacySafe() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  2360,
  '66158fdf4ab78598d757c0f4411ee3f56d559f109f11fe7aa3af3d09df60a1f2',
  (),
  (('optionalTry', 189, ()),),
  ('guard case .maintenance(.finalizationInconsistent) = router.route else {',
   'XCTAssertEqual(try DiagnosticExportCanonicalEncoderV1.encode(prepared.value), prepared.canonicalData)',
   'let object = try XCTUnwrap(JSONSerialization.jsonObject(with: prepared.canonicalData) as? [String: Any])',
   'let text = try XCTUnwrap(String(data: prepared.canonicalData, encoding: .utf8))'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testCorruptReceiptHistoryMaintenanceSalvageSavesPhotosAndReportsReadOnly() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  5123,
  '8fae6b1cafc0617e110c5338779008d75ede5f133acedc86137a25d6caafd635',
  (),
  (('optionalTry', 188, ()), ('optionalTry', 3268, ())),
  ('guard case .maintenance = router.route else { return XCTFail("Expected maintenance, got '
   '\\(router.route)") }',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n    func testMaintenanceSalvageWithNothingToSaveReportsStatus() async throws {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  1490,
  'baa0ebd05e12244a6858187425aed31e0e28caadc984f45a92aa93985311d261',
  (),
  (('optionalTry', 168, ()), ('optionalTry', 600, ())),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    private func makeStartupApplicationSupportURL() throws -> URL {',
  ('final class S2PersistenceLedgerTests: XCTestCase {',),
  1,
  277,
  'd07de34e5a712302a61b3831a80cef942a8ad036735397fee5ae9b2df56e615d',
  (),
  (('optionalTry', 158, ()),),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n    func testStartupRecoversPendingPDFAndPublishesItsSingleWriter() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  2774,
  '083cdf8cd48dd98e7a0f63a8887d8c18ebd48a62a0880a4402ec69ef20ea1a6d',
  (),
  (('optionalTry', 542, ()), ('optionalTry', 1277, ())),
  ('guard case let .ready(coordinator, _, _) = router.route else {',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testStartupRetryAndUnsafePDFFailureExplicitlyReleaseRetainedPublishedWriters() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  1839,
  '6c6c3ee6e4a8ac4c9da0e3dbeb686f53c91c61b2c64f29eb12efe7acff97e92b',
  (),
  (('optionalTry', 192, ()),),
  ('guard case let .ready(first, _, _) = router.route else { return XCTFail("Initial startup") }',
   'guard case let .ready(second, _, _) = router.route else { return XCTFail("Explicit retry") }',
   'guard case .maintenance(.finalizationInconsistent) = router.route else {'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testStartupReleaseFailureRemainsOwnedAndBlocksRetryUntilOriginalRegistryIsReadable() async '
  'throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  2568,
  'fd2081b8315c9f31c4cfd82721600726a6a9d33199f714eb4900b7e5f33fb288',
  (),
  (('optionalTry', 198, ()), ('optionalTry', 1208, ())),
  ('guard case let .ready(coordinator, _, _) = router.route else { return XCTFail("Initial startup") }',
   'guard case let .ready(retried, _, _) = router.route else { return XCTFail("Release retry must recover") '
   '}'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n    func testSupersededStartupCannotPublishOrClearTheNewReadyOperation() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  1934,
  '7c8cf14e93dd3156f0886346e156a54035d94f74b29af2f89fdb13ccdb0c6628',
  (),
  (('optionalTry', 177, ()),),
  ('guard case let .ready(current, _, _) = router.route else {',
   'guard case let .ready(stillCurrent, _, _) = router.route else { return XCTFail("Stale completion '
   'overwrote ready") }'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testAppAccessRevocationDuringSuspendedStartupCannotPublishOrReviveCommerce() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  2164,
  '56167644f5970d9420e377a4cb2b7e310a7eec9a6cb6c8a48ab04ff34deac6bd',
  (),
  (('optionalTry', 190, ()),),
  ('return nil', '} catch {', 'guard case .checking = router.route else {'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testToggleNotificationUsesSettledPreparedOwnerThenOrdinaryStartupAdoptsIt() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  3967,
  'f2866f16f1c7063035f577e1c258a6c1d0556ab9993fc74874635412e99a497d',
  (),
  (('optionalTry', 189, ()),),
  ('guard case let .ready(initial, _, _) = router.route else {',
   'guard case .checking = router.route else {',
   '} catch {',
   'guard case let .ready(adopted, _, _) = router.route else {'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testConfigurationNotificationStartupPreparesThenOrdinaryStartupAdoptsTheSameWriter() async '
  'throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  3250,
  'd348a5dee699d5f274f21b58a70c630e75151a44ee7eb0b8d8859fd80a022b42',
  (),
  (('optionalTry', 198, ()),),
  ('guard case .checking = router.route else {',
   'guard case let .ready(coordinator, _, _) = router.route else {'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testDeferredEraseRetainsLiveOldContextAcrossAppAccessResumeUntilDrain() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  15998,
  '7c9e40e40527652b6ebe4a5ae3f7aef14a6dc214b3a408e55e8f4c2efe145259',
  (),
  (('print', 2049, ()), ('print', 2834, ())),
  ('guard firstStartupFailure == nil else { return }',
   'guard case .ready = router.route else {',
   'guard let reservation = eraseReservation,',
   'throw AppAccessContractFailureV1.staleAttempt',
   '} catch {',
   'guard case let .eraseCleanupPending(.retiring(pendingCoordinator)) = router.route else {',
   'guard case let .eraseCleanupPending(.retiring(heldCoordinator)) = router.route else {',
   '} catch { }',
   'guard case let .eraseCleanupPending(.retiring(recoveredHeldCoordinator)) = router.route else {',
   'guard let liveOldContext = retainedOldContext,',
   'guard oldStateIsReleased() else {',
   'guard completed else { throw AppAccessContractFailureV1.staleAttempt }',
   'guard case let .ready(recoveredCoordinator, _, _) = router.route else {'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testSuspendedRestoredActivationCannotReleaseANewerBindingInTheSameCoordinator() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  2144,
  '42a61063d8474645ba153c79af2ec0858674c398b17f3a834250ff96fcf317d4',
  (),
  (('optionalTry', 195, ()),),
  ('guard case .maintenance(.finalizationInconsistent) = router.route else {',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    private func makePostAdoptionEraseFixture(\n'
  '        beforePostAdoptionContentRead: @escaping @MainActor (UUID) async -> Void = { _ in },\n'
  '        willReadPostAdoptionCanonicalContent: @escaping @MainActor (UUID) -> Void = { _ in },\n'
  '        beforeCommerceActivation: @escaping @MainActor (UUID) async -> Void = { _ in },\n'
  '        cleanupCase: EraseCleanupCase = .ordinary\n'
  '    ) async throws -> S2PostAdoptionEraseFixture {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  15665,
  '83f3d54d91757f300467e013d326fbbc91511b54f9d37c5ed074f06919b6f81e',
  (),
  (('print', 2462, ()), ('print', 3037, ())),
  ('guard forwardsPostAdoptionHooks else { return }',
   'guard firstStartupFailure == nil else { return }',
   'guard case .ready = router.route else {',
   'throw AppAccessContractFailureV1.staleAttempt',
   'guard let reservation, reservation.subject == subject else {',
   '} catch { activationFailure = error }',
   'if let activationFailure { throw activationFailure }',
   'guard oldCoordinator == nil, oldWriter == nil else {',
   'guard oldContextIsReleased() else { throw AppAccessContractFailureV1.staleAttempt }',
   '} catch { }',
   'guard case let .eraseCleanupPending(.retiring(held)) = router.route else {',
   'guard completedCleanup else { throw AppAccessContractFailureV1.staleAttempt }',
   '} catch {',
   'throw originalError'),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testErasedActivationMismatchAndRepeatedBeginReleaseOnlyTheAcquiredWriter() async throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  2831,
  '37c89b952f10b8f0835dc636578f8e5b31a55a62cb0570e1f140b6fabbe950a4',
  (),
  (('optionalTry', 338, ()), ('optionalTry', 392, ())),
  ('guard case .maintenance(.eraseInconsistent) = router.route else {',),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift',
  '    @MainActor\n'
  '    func testValidatingCoordinatorConstructionReleasesLeaseAfterRealJournalFailure() throws {',
  ('extension S2PersistenceLedgerTests {',),
  1,
  1304,
  '74eec265e4ab49672c12f7e6e61782ce938a539d1b80bc837cf5c70a5819929c',
  (),
  (('optionalTry', 185, ()),),
  (),
  ('Exact XCTest method/assertion/fixture cleanup; nil boundary count fails; registry restored under named '
   'guard; actual StartupRouter DEBUG type/phase callback.',)),
 ('FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift',
  '    func testDiagnosticsRejectsRootReplacementDuringHeldPublicationWithoutChangingBytes() async throws {',
  ('@MainActor\nfinal class V9_12SystemHealthOperationalDiagnosticsTests: XCTestCase {',),
  1,
  1895,
  'a05244ae2af1632b79897e2395530e0f6e188540f44bb66d46e1c66852a5c288',
  (),
  (('optionalTry', 392, ()), ('optionalTry', 450, ())),
  ('} catch {',),
  ('Exact XCTest owner/assertions and disjoint temporary-root cleanup; no production authorization.',)),
 ('FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift',
  '    func testV9_12A01OperationalFailureRegistryAndDefaultOffFrictionAreClosed() async throws {',
  ('@MainActor\nfinal class V9_12SystemHealthOperationalDiagnosticsTests: XCTestCase {',),
  1,
  8555,
  '543be6ea858ab74c3d198e9b4367d3bdc9e69c95d82abc3d5d735874918c7c4d',
  (),
  (('optionalTry', 3587, ()), ('optionalTry', 4752, ())),
  ('throw StoreMigrationFailure.invalidDigest', '} catch {'),
  ('Exact XCTest owner/assertions and disjoint temporary-root cleanup; no production authorization.',)),
 ('FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift',
  '    func testV9_12I01StoreScratchAndSupportExportRecoverWithoutDuplicateEffects() async throws {',
  ('@MainActor\nfinal class V9_12SystemHealthOperationalDiagnosticsTests: XCTestCase {',),
  1,
  16640,
  'c939db3029455b60066774ea1514762d886a0ea8b68e41489a5125f1105e654b',
  (),
  (('optionalTry', 205, ()),
   ('optionalTry', 4756, ()),
   ('optionalTry', 5533, ()),
   ('optionalTry', 7412, ()),
   ('optionalTry', 9410, ()),
   ('optionalTry', 12136, ())),
  ('guard written == bytes.count else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }',
   'throw SemanticReadWitness.interrupted'),
  ('Exact XCTest owner/assertions and disjoint temporary-root cleanup; no production authorization.',)),
 ('FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift',
  '    func testV9_12R01MigrationResetEraseAndBootstrapRemainDeviceLocal() async throws {',
  ('@MainActor\nfinal class V9_12SystemHealthOperationalDiagnosticsTests: XCTestCase {',),
  1,
  11326,
  '361aaf6488b37fc1534a7da3d952c86983de02bf76a29314a3bc9ce852a31dd1',
  (),
  (('optionalTry', 195, ()),
   ('optionalTry', 929, ()),
   ('optionalTry', 1772, ()),
   ('optionalTry', 2544, ()),
   ('optionalTry', 3805, ()),
   ('optionalTry', 9623, ())),
  ('} catch {',
   'corruptObject["feedbackDraftRecoveryRequired"] = "not-a-boolean"',
   '.appendingPathComponent(".counters.json.quarantine").path',
   'throw V912Failure.unexpectedCanonicalOpen'),
  ('Exact XCTest owner/assertions and disjoint temporary-root cleanup; no production authorization.',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'enum StartupMaintenanceReason: String, CaseIterable, Error, Sendable {',
  (),
  0,
  463,
  'f80a6bc113cf3ee2c5294df9dd3d748a320526916fe0a3d6cd22393542add473',
  (),
  (),
  (),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'enum StartupRuntimeObservationPhaseV1: String, Equatable, Sendable {',
  (),
  0,
  307,
  '60dbe40a97e702afa0d08cda5fedc198bb35cb7eb0580f4260018ec275dbe413',
  ('if DEBUG',),
  (),
  (),
  ('Closed typed DEBUG/sole-adapter registry/identity owner; complete members and scalar labels conserved',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  '    private func reportStartupFailureForTesting(_ error: Error) {',
  ('@MainActor\nfinal class StartupRouter: ObservableObject {',),
  1,
  518,
  '7b64d15985a57d2a34bebd7cbba4ca8bbb5758a87a19547628c80d5457d3f4c5',
  ('if DEBUG',),
  (),
  ('guard let observe = startupFailureDiagnosticForTesting else { return }',
   'observe("phase=\\(phase) type=\\(errorType) resourceValueMismatch=\\(policyMismatch) '
   'currentOpenBoundary=\\(currentOpenBoundaryForTesting)")'),
  ('DEBUG immutable fixed phase/runtime error TYPE/boolean/closed open-boundary callback',
   'Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure')),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  '    private func runStartup(authorization: StartupAuthorization?, coldEraseService: EraseAllService? = '
  'nil) async {',
  ('@MainActor\nfinal class StartupRouter: ObservableObject {',),
  1,
  22800,
  '7340a1e163853675eb22dcde8a044fd9a950ebdbb3cdf0bc7fd905d6c352bbc7',
  (),
  (),
  ('guard !isRunning else {',
   'catch { lastStartupAccessFailure = error; return }',
   'guard !isRunning else { return }',
   'guard resolvePendingWriterCleanup() else {',
   '} catch {',
   'guard pendingEraseDrainProof.isDrained else {',
   'guard !maintenanceOperationsUncertain else {',
   'let savedErrno = errno',
   'defer { errno = savedErrno }',
   'catch { /* Diagnostic transport never replaces the actual refusal. */ }',
   'throw StartupMaintenanceReason.eraseInconsistent',
   'throw StartupMaintenanceReason.restoreInconsistent',
   'currentOpenBoundaryForTesting = "session-select"',
   'currentOpenBoundaryForTesting = "factory-open"',
   'currentOpenBoundaryForTesting = "maintenance-frame"',
   'currentOpenBoundaryForTesting = "lease-reconcile"',
   'throw StartupMaintenanceReason.dataPointerInvalid',
   'throw StartupMaintenanceReason.fieldDraftInconsistent',
   'guard let ordinary = coldFreshOwner.ordinaryFactory else {',
   'throw GenerationLeaseRegistryFailureV1.uncertainOwner',
   '} catch let reason as StartupMaintenanceReason {',
   'throw reason',
   'throw StartupMaintenanceReason.finalizationInconsistent',
   'maintenanceOperationsUncertain = true',
   'throw StartupMaintenanceReason.mediaInconsistent',
   'guard operationID == operation else {'),
  ('Complete actual named diagnostic caller preserves literal/enum arguments, checked operations and '
   'original failure',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift',
  '    deinit {',
  ('final class StoreRestoreGenerationAuthority {',),
  1,
  441,
  '828361300bfeefee56b28dd428205ff55ce6b3c6fc073cc93ba128996c50f7b2',
  (),
  (),
  ('if !originalRecoveryCloseAttempted && !eraseRetirementTerminalCloseAttempted {',),
  ('Uncertain/attempted original close is never retried by deinit',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift',
  '    func closeCheckedForOriginalRecovery() throws {',
  ('final class StoreRestoreGenerationAuthority {',),
  1,
  1276,
  'c8b466bd6ebb306b738b69b02080394fb63de747d0f93222e0b59f93c25660fe',
  (),
  (),
  ('guard originalRecoveryNoCreate, !originalRecoveryCloseAttempted else {',
   'throw StoreGenerationFailure.dataPointerInvalid',
   'originalRecoveryCloseAttempted = true',
   'catch {',
   'Self.originalRecoveryUncertainCloseLock.withLock {',
   'Self.originalRecoveryUncertainDescriptors.append(contentsOf: [',
   'throw error',
   'var uncertain = false',
   'Self.originalRecoveryUncertainDescriptors.append(fd)',
   'uncertain = true',
   'guard !uncertain else { throw StoreGenerationFailure.dataPointerInvalid }'),
  ('Six descriptors; attempted flag, uncertainty quarantine, original-error rethrow; no retry',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift',
  '    static func classify(_ path: String, nodeType: NodeType) throws -> Classification {',
  ('enum GenerationOwnedPathV1 {',),
  1,
  4380,
  'a729716dae465300b0674dfb1458df513a10eab5fc7c90bd817eefd7c6433057',
  (),
  (),
  ('guard StoreGenerationFileDigestV1.isCanonicalRelativePath(path) else {',
   'throw StoreMigrationFailure.invalidPath'),
  ('Closed structural owned-kind classification only; diagnostic nil becomes unknown, never authority',)),
 ('FieldEvidenceApp/Domain/Scheduling/ScheduleOverrideContractsV1.swift',
  '    func validateSuccessor(of predecessor: Self) throws {',
  ('struct ScheduleOverrideEventV1: Codable, Equatable, Sendable {',),
  1,
  631,
  '1e91b7e683b5a77ed7fadf0c0c9b5a2bbef9fbccadea4b3f4cc71d889a7d8e7e',
  (),
  (),
  ('guard predecessor.workspaceID == workspaceID,', 'throw ScheduleFailureV1.invalidSuccessor'),
  ('Checked genuine predecessor graph relation',)),
 ('FieldEvidenceApp/Domain/Scheduling/ScheduleOverrideContractsV1.swift',
  '    static func activeEvents(_ events: [ScheduleOverrideEventV1]) throws -> [ScheduleOverrideEventV1] {',
  ('enum ScheduleOverridePrecedenceV1 {',),
  1,
  1014,
  '24a90709f6a1a377cf51cac43b90a405765131134118552c6b94c6b93a9493f6',
  (),
  (),
  ('guard Set(events.map(\\.eventID)).count == events.count else { throw ScheduleFailureV1.divergentReplay }',
   'guard let predecessorID = event.supersedesEventID, let predecessor = byID[predecessorID] else {',
   'throw ScheduleFailureV1.staleBasis',
   'try event.validateSuccessor(of: predecessor)'),
  ('Complete graph validates each event, duplicate IDs, predecessor and successor then computes sorted '
   'active set',)),
 ('FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift',
  '    func testAdvancedScheduleDiagnosticsRejectInvalidOverrideGraphsAndRetainValidCounts() throws {',
  ('final class S8_3DiagnosticPrivacyTests: XCTestCase {',),
  1,
  5507,
  '42072364350c48293e8b3316ede95518e0fc118eb1360fe17d03b5e6a99241f9',
  (),
  (),
  ('XCTAssertTrue(value.isValid)', 'XCTAssertEqual(value.activeOverrideCount, expectedActiveCount)'),
  ('Valid graph counts plus duplicate/divergent/stale typed failures',)),
 ('FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift',
  '    @MainActor\n    func testColdDiagnosticsBoundaryLabelsExcludeAssociatedValuesAndFailClosed() throws {',
  ('final class S8_3DiagnosticPrivacyTests: XCTestCase {',),
  1,
  3512,
  'd3f01e196bb6703b0707abc115cb06b5bae745990e71ceedf0af5d05b10cf8a8',
  ('if DEBUG',),
  (),
  (),
  ('Actual primitive descriptions, hostile URL/UUID/data exclusion, closed labels and unknown fallback',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  '    static func emit(owner: String, stage: String, error: Error,\n'
  '        started: UInt64, stageStarted: UInt64) {',
  ('enum OriginalEraseScratchFirstErrorDiagnosticV1 {',),
  1,
  655,
  '062a6e7c467eaab7f0454120968b439f19d7d521b81f2ed360a45fead5664185',
  ('if DEBUG',),
  (),
  ('let saved = errno', 'defer { errno = saved }'),
  ('Complete actual admitted emitter declaration/producer-caller adjacency; non-try stderr privacy/runtime '
   'remains UNVERIFIED, no new output exemption',)),
('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
 '    static func reportExistingLeavesForTesting(\n        before: Self, after: Self\n    ) {',
 ('struct EraseOriginalNotificationPhysicalSnapshotV1: Equatable {',),
 1,
 5488,
 '6ee66ebc653039cdd9ca63dc45bf1d62be631fc54a41926ef25fe0181f52c5a8',
 ('if DEBUG',),
 (('optionalTry', 5418, ('if DEBUG',)),),
 ('let savedErrno = errno',
  'defer { errno = savedErrno }',
  'oldLinks < UInt64.max, newLinks == oldLinks + 1',
  'let capturedTokens = before.diagnosticNodes == after.diagnosticNodes ? "same" : "different"',
  'try? FileHandle.standardError.write(contentsOf: Data(line.utf8))'),
 ('Closed DEBUG relationships of the actual retained notification pair; observed plus-one never '
  'authenticates or projects. Captured walk facts only, no new filesystem reads; fixed categories exclude '
  'raw paths, names, values, SHA and contents. Local transport-only optional try preserves errno and cannot '
  'replace the original outcome.',)),
('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
 '    func afterOriginalNotificationRevocation(\n'
 '        _ revocation: NotificationEraseRevocationV1\n'
 '    ) throws {',
 ('private final class EraseOriginalColdExitFrameV1: @unchecked Sendable {',),
 1,
 2839,
 '51409641fbb27aabce65744a82c1031b4f1015c19497acadb220dafc99a966cc',
 ('if DEBUG',),
 (),
 ('let expected = try CompatibilityCanonicalV1.encode(revocation)',
  'before: notificationBeforeEffect, after: actual',
  'actual.rootDevice == notificationBeforeEffect.rootDevice',
  'actual.rootInode == notificationBeforeEffect.rootInode',
  'actual.unchangedLeavesDigest\n                        == notificationBeforeEffect.unchangedLeavesDigest',
  'actual.eraseBytes == expected',
  'actual.eraseIdentity != nil',
  'actual.names == (notificationBeforeEffect.names',
  'else { throw EraseAllServiceError.invalidAuthority }',
  'try requireSearchPublished()',
  'notificationAfterRevocation = actual',
  'throw error'),
 ('Exact complete genuine afterBegin caller and retained before/after arguments; all six original ordered '
  'short-circuit guards, original error object/rethrow, encode/read/reproof and mutation order preserved. '
  'Diagnostic-only call cannot authorize or project either cut.',)))

CURRENT_C08_HARDENING_CALLERS = (('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'OriginalEraseScratchFirstErrorDiagnosticV1.emit(',
  67,
  183,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'OriginalEraseScratchFirstErrorDiagnosticV1.emitSourceCutMembers(',
  77,
  94,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'OriginalEraseScratchFirstErrorDiagnosticV1.emitSourceCutError(',
  76,
  5950,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  58,
  13,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  59,
  550,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  59,
  1105,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  59,
  1245,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  59,
  2163,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  59,
  3069,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  59,
  3241,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  59,
  3358,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic(',
  65,
  7423,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  84,
  17,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  65,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  280,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  753,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  1047,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  1576,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  1927,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  2207,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  2522,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  2679,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  3282,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  3417,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  4429,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  86,
  4553,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  343,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  439,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  509,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  613,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  1240,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  5153,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  10236,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  10938,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  11526,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  11942,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  12021,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic(',
  87,
  12146,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'withColdOwnedIDsReserveDiagnostic(',
  87,
  269,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  145,
  17,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  6904,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  8021,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  10852,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  11282,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  13163,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  14423,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  16324,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  16795,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  17646,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  19178,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting(',
  146,
  20324,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting =',
  None,
  6218,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting =',
  146,
  8422,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting =',
  146,
  8965,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting =',
  146,
  10358,
  ('if DEBUG',)),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting =',
  146,
  10509,
  ('if DEBUG',)),
('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
 'EraseOriginalNotificationPhysicalSnapshotV1.reportExistingLeavesForTesting(',
 156,
 1002,
 ('if DEBUG',)))


CURRENT_C08_HARDENING_PROTECTED_IDENTIFIERS = ('emit',
 'emitSourceCutMembers',
 'emitSourceCutError',
 'reportOriginalNotificationRootDiagnostic',
 'advanceColdOwnedIDsReserveDiagnostic',
 'withColdOwnedIDsReserveDiagnostic',
 'reportStartupFailureForTesting',
 'currentOpenBoundaryForTesting',
 'ColdOwnedIDsReserveDiagnosticContextV1',
 'coldOwnedIDsReserveDiagnostic',
 'Logger',
 'os_log',
 'OSSignposter',
 'NSLog',
 'debugPrint',
 'print',
'reportExistingLeavesForTesting')

CURRENT_C08_HARDENING_REFERENCES = (('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift', 'print', 0, 427, None),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift', 'print', 3, 12216, None),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift', 'print', 11, 8057, None),
 ('FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift', 'Logger', 53, 326, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'emit', 154, 16, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'emit', 67, 226, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'emitSourceCutMembers', 55, 16, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'emitSourceCutMembers',
  77,
  137,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'emitSourceCutError', 56, 16, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'emitSourceCutError', 76, 5993, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  58,
  13,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  59,
  550,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  59,
  1105,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  59,
  1245,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  59,
  2163,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  59,
  3069,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  59,
  3241,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  59,
  3358,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'reportOriginalNotificationRootDiagnostic',
  65,
  7423,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  84,
  17,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  65,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  280,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  753,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  1047,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  1576,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  1927,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  2207,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  2522,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  2679,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  3282,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  3417,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  4429,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  86,
  4553,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  343,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  439,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  509,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  613,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  1240,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  5153,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  10236,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  10938,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  11526,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  11942,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  12021,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'advanceColdOwnedIDsReserveDiagnostic',
  87,
  12146,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'withColdOwnedIDsReserveDiagnostic',
  85,
  17,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'withColdOwnedIDsReserveDiagnostic',
  87,
  269,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'ColdOwnedIDsReserveDiagnosticContextV1',
  81,
  35,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'ColdOwnedIDsReserveDiagnosticContextV1',
  None,
  55,
  ('    private var coldOwnedIDsReserveDiagnostic:\n        ColdOwnedIDsReserveDiagnosticContextV1?',
   ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
    '    Schema2ColdNotificationEraseControlV1 {',))),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'ColdOwnedIDsReserveDiagnosticContextV1',
  85,
  212,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'coldOwnedIDsReserveDiagnostic',
  None,
  16,
  ('    private var coldOwnedIDsReserveDiagnostic:\n        ColdOwnedIDsReserveDiagnosticContextV1?',
   ('@MainActor final class EraseSchema2ColdNotificationControlV1:\n'
    '    Schema2ColdNotificationEraseControlV1 {',))),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'coldOwnedIDsReserveDiagnostic',
  84,
  145,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'coldOwnedIDsReserveDiagnostic',
  85,
  160,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'coldOwnedIDsReserveDiagnostic',
  85,
  335,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
  'coldOwnedIDsReserveDiagnostic',
  85,
  391,
  None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'print', 58, 139, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'print', 58, 249, None),
 ('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift', 'print', 61, 1099, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'emit', 96, 37855, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 88, 753, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 88, 1161, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 91, 125, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 92, 593, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 94, 369, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 95, 1271, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 95, 2043, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 96, 37346, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
  'print',
  None,
  50,
  ('/// Names and digests stay in memory; diagnostics print fixed categories only.', ())),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 569, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 888, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 1092, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 1848, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 2193, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 2279, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 2746, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 3669, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 4685, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 5316, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 5452, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 5663, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 5959, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 8816, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 9514, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 9846, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 10046, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 10786, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 12718, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 13219, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 13798, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 14363, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 14987, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 15733, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 16325, None),
 ('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift', 'print', 101, 16540, None),
 ('FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift',
  'print',
  102,
  141,
  None),
 ('FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift', 'print', 105, 199, None),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift', 'print', 134, 2049, None),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift', 'print', 134, 2834, None),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift', 'print', 136, 2462, None),
 ('FieldEvidenceAppTests/S2PersistenceLedgerTests.swift', 'print', 136, 3037, None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  145,
  17,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  6904,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  8021,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  10852,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  11282,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  13163,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  14423,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  16324,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  16795,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  17646,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  19178,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'reportStartupFailureForTesting',
  146,
  20324,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting',
  None,
  16,
  ('    private var currentOpenBoundaryForTesting = "unobserved"',
   ('@MainActor\nfinal class StartupRouter: ObservableObject {',))),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting',
  145,
  480,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting',
  146,
  8422,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting',
  146,
  8965,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting',
  146,
  10358,
  None),
 ('FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift',
  'currentOpenBoundaryForTesting',
  146,
  10509,
  None),
('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift',
 'reportExistingLeavesForTesting',
 155,
 16,
 None),
('FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift',
 'reportExistingLeavesForTesting',
 156,
 1046,
 None))


def _current_c08_hardening_conditions(code: str, position: int) -> tuple[str, ...]:
    """Actual lexical branch ownership; DEBUG is never a file-level exemption."""
    stack: list[str] = []
    for line in code[:position].splitlines():
        match = re.match(r"^[ \t]*#(if|elseif|else|endif)\b(.*)", line)
        if match is None:
            continue
        directive, condition = match.group(1), match.group(2).strip()
        if directive == "if":
            stack.append("if " + condition)
        elif directive in ("else", "elseif"):
            require(bool(stack), "current C08 hardening: conditional ownership differs")
            stack[-1] = directive + (" " + condition if condition else "")
        else:
            require(bool(stack), "current C08 hardening: conditional ownership differs")
            stack.pop()
    return tuple(stack)


def _current_c08_hardening_frame(
    source: str, code: str, policy: tuple, label: str,
) -> tuple[int, int]:
    """Bind a code-anchored header, exact owners and the declaration's own brace.

    The reviewed current declaration digest preserves every operand, check,
    catch/poison/close/rethrow and assertion, in addition to explicit clauses.
    It is neither an exception for an entire file nor permission for another
    use of the same callee. Legitimate changed declarations require review.
    """
    import hashlib

    (_, header, owners, depth, byte_count, digest, conditions,
     _, fact_clauses, _) = policy
    possible = []
    for start in _current_c08_code_matches(source, header, code):
        opening = start + len(header) - 1
        require(code[opening] == "{",
                f"current C08 hardening: {label} own opening brace differs")
        end = _current_c08_balanced_end(code, opening, label)
        if code[:start].count("{") - code[:start].count("}") != depth:
            continue
        selected_owners = []
        for owner in owners:
            enclosing = []
            for owner_start in _current_c08_code_matches(source, owner, code):
                owner_opening = owner_start + len(owner) - 1
                if code[owner_opening] != "{" or owner_start >= start:
                    continue
                owner_end = _current_c08_balanced_end(code, owner_opening, label)
                if end <= owner_end:
                    enclosing.append((owner_start, owner_end))
            if len(enclosing) != 1:
                break
            selected_owners.append(enclosing[0])
        if len(selected_owners) != len(owners):
            continue
        if any(not (left[0] < right[0] < right[1] <= left[1])
               for left, right in zip(selected_owners, selected_owners[1:])):
            continue
        if selected_owners and not (
            selected_owners[-1][0] < start < end <= selected_owners[-1][1]
        ):
            continue
        possible.append((start, end))
    require(len(possible) == 1,
            f"current C08 hardening: {label} declaration/owner identity differs")
    start, end = possible[0]
    require(_current_c08_hardening_conditions(code, start) == conditions,
            f"current C08 hardening: {label} conditional ownership differs")
    block, block_code = source[start:end], code[start:end]
    require(all(_current_c08_code_matches(block, token, block_code)
                for token in fact_clauses),
            f"current C08 hardening: {label} checked failure/identity clauses differ")
    raw = block.encode("utf-8")
    require(len(raw) == byte_count and hashlib.sha256(raw).hexdigest() == digest,
            f"current C08 hardening: {label} complete checked declaration differs")
    return start, end


def _current_c08_hardening_callers(
    texts: dict[str, str], codes: dict[str, str], frames: list[tuple[int, int]],
) -> None:
    """Closed actual producer/caller census, including identity and error flow."""
    groups: dict[tuple[str, str], list[tuple]] = {}
    for relative, token, frame_index, offset, conditions in CURRENT_C08_HARDENING_CALLERS:
        groups.setdefault((relative, token), []).append((frame_index, offset, conditions))
    for (relative, token), rows in groups.items():
        source, code = texts[relative], codes[relative]
        actual = _current_c08_code_matches(source, token, code)
        expected = []
        for frame_index, offset, conditions in rows:
            if frame_index is None:
                # Sole DEBUG field initializer, not a mock global or arbitrary
                # String assignment. All actual writes are separately bound to
                # runStartup's complete method and closed caller census below.
                statement = 'private var currentOpenBoundaryForTesting = "unobserved"'
                positions = _current_c08_code_matches(source, statement, code)
                require(len(positions) == 1 and
                        code[:positions[0]].count("{") -
                        code[:positions[0]].count("}") == 1,
                        "current C08 hardening: startup boundary initializer differs")
                position = positions[0] + statement.index(token)
                require(position == offset,
                        "current C08 hardening: startup boundary declaration position differs")
            else:
                require(type(frame_index) is int and 0 <= frame_index < len(frames) and
                        CURRENT_C08_HARDENING_DECLARATIONS[frame_index][0] == relative,
                        "current C08 hardening: actual caller policy join differs")
                start, end = frames[frame_index]
                position = start + offset
                require(start <= position < end,
                        "current C08 hardening: actual caller leaves its own declaration")
            require(source.startswith(token, position) and
                    not code[position].isspace() and
                    _current_c08_hardening_conditions(code, position) == conditions,
                    "current C08 hardening: actual caller/DEBUG branch differs")
            expected.append(position)
        require(len(expected) == len(set(expected)) and sorted(expected) == actual,
                f"current C08 hardening: complete caller census differs: {relative}: {token}")

    # Bind all raw protected identifiers, including references without call
    # parentheses, aliases, alternate qualifier spacing and executable Swift
    # interpolation. The inherited code mask intentionally masks strings, so
    # it is insufficient for this producer census. Unknown raw references in
    # strings/comments also refuse; they never authorize a code occurrence.
    # This is a closed Source-profile check, not a file/DEBUG/callee exemption.
    symbols = (
        "emit", "emitSourceCutMembers", "emitSourceCutError",
        "reportOriginalNotificationRootDiagnostic",
        "advanceColdOwnedIDsReserveDiagnostic", "withColdOwnedIDsReserveDiagnostic",
        "reportStartupFailureForTesting", "currentOpenBoundaryForTesting",
        "ColdOwnedIDsReserveDiagnosticContextV1", "coldOwnedIDsReserveDiagnostic",
        "Logger", "os_log", "OSSignposter", "NSLog", "debugPrint", "print",
        "reportExistingLeavesForTesting",
    )
    require(type(CURRENT_C08_HARDENING_PROTECTED_IDENTIFIERS) is tuple and
            CURRENT_C08_HARDENING_PROTECTED_IDENTIFIERS == symbols and
            type(CURRENT_C08_HARDENING_REFERENCES) is tuple and
            len(CURRENT_C08_HARDENING_REFERENCES) == 120,
            "current C08 hardening: protected reference policy census differs")
    primary = tuple(path for path in EXISTING_PATHS + NEW_SOURCE_PATHS
                    if path.endswith(".swift"))
    references: dict[tuple[str, str], list[int]] = {}
    for row in CURRENT_C08_HARDENING_REFERENCES:
        require(type(row) is tuple and len(row) == 5,
                "current C08 hardening: protected reference policy shape differs")
        relative, identifier, frame_index, offset, unframed = row
        require(relative in codes and identifier in symbols and type(offset) is int and
                offset >= 0 and (identifier != "print" or relative in primary),
                "current C08 hardening: protected reference input join differs")
        source, code = texts[relative], codes[relative]
        if frame_index is not None:
            require(type(frame_index) is int and 0 <= frame_index < len(frames) and
                    CURRENT_C08_HARDENING_DECLARATIONS[frame_index][0] == relative and
                    unframed is None,
                    "current C08 hardening: protected reference declaration join differs")
            start, end = frames[frame_index]
            position = start + offset
            require(start <= position and position + len(identifier) <= end,
                    "current C08 hardening: protected reference leaves its own declaration")
        else:
            require(type(unframed) is tuple and len(unframed) == 2 and
                    type(unframed[0]) is str and type(unframed[1]) is tuple,
                    "current C08 hardening: protected field/comment role shape differs")
            literal, owners = unframed
            matches = [match.start() for match in re.finditer(re.escape(literal), source)]
            require(len(matches) == 1 and offset + len(identifier) <= len(literal),
                    "current C08 hardening: protected field/comment literal role differs")
            start, end = matches[0], matches[0] + len(literal)
            position = start + offset
            if owners:
                # The two genuine private fields remain direct members of
                # their actual named types, never a moved extension/property
                # or a literal containing a purported field declaration.
                require(_current_c08_code_matches(source, literal, code) == [start] and
                        code[:start].count("{") - code[:start].count("}") == len(owners),
                        "current C08 hardening: protected field code/depth differs")
                require(_current_c08_hardening_conditions(code, start) == ("if DEBUG",),
                        "current C08 hardening: protected field conditional ownership differs")
                selected = []
                for owner in owners:
                    enclosing = []
                    for owner_start in _current_c08_code_matches(source, owner, code):
                        owner_opening = owner_start + len(owner) - 1
                        if code[owner_opening] != "{" or owner_start >= start:
                            continue
                        owner_end = _current_c08_balanced_end(
                            code, owner_opening, "protected field owner")
                        if end <= owner_end:
                            enclosing.append((owner_start, owner_end))
                    require(len(enclosing) == 1,
                            "current C08 hardening: protected field owner identity differs")
                    selected.append(enclosing[0])
                require(all(left[0] < right[0] < right[1] <= left[1]
                            for left, right in zip(selected, selected[1:])),
                        "current C08 hardening: protected field owner nesting differs")
            else:
                require(literal.startswith("///") and identifier == "print",
                        "current C08 hardening: unframed role is not the known Source comment")
        require(source.startswith(identifier, position),
                "current C08 hardening: protected reference literal position differs")
        references.setdefault((relative, identifier), []).append(position)
    for relative in codes:
        for identifier in symbols:
            # Historical print scope is the original fourteen Swift inputs.
            # Other protected producer identities use the explicit supporting
            # declaration/caller read set as well; no supporting output waiver.
            if identifier == "print" and relative not in primary:
                continue
            actual = [match.start() for match in re.finditer(
                r"(?<![A-Za-z0-9_])" + re.escape(identifier) + r"(?![A-Za-z0-9_])",
                texts[relative])]
            positions = references.get((relative, identifier), [])
            require(len(positions) == len(set(positions)) and sorted(positions) == actual,
                    f"current C08 hardening: unregistered protected reference: {relative}: {identifier}")


def verify_current_source_hardening() -> None:
    """Complete current hardening; historical card checks remain unchanged.

    Scope is the original fourteen whole Swift inputs and all fifteen presence
    bindings, plus five exact supporting Source inputs. The 106 optional-try
    and 46 print sites have complete declaration/owner/conditional/caller
    bindings; there are no file, DEBUG or callee-name exceptions. Preexisting
    non-try stderr emissions were outside the historical output predicate and
    remain UNVERIFIED, with no additional exemption or privacy claim here.
    """
    paths = tuple(EXISTING_PATHS + NEW_SOURCE_PATHS)
    support = (
        "FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift",
        "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
        "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
        "FieldEvidenceApp/Domain/Scheduling/ScheduleOverrideContractsV1.swift",
        "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    )
    require(len(paths) == len(set(paths)) == 15 and
            sum(path.endswith(".swift") for path in paths) == 14,
            "current C08 hardening: complete fifteen/fourteen-path census differs")
    require(type(CURRENT_C08_HARDENING_SUPPORT_PATHS) is tuple and
            CURRENT_C08_HARDENING_SUPPORT_PATHS == support and
            len(set(paths + support)) == 20,
            "current C08 hardening: complete supporting-input closure differs")
    require(type(CURRENT_C08_HARDENING_DECLARATIONS) is tuple and
            len(CURRENT_C08_HARDENING_DECLARATIONS) == 157 and
            type(CURRENT_C08_HARDENING_CALLERS) is tuple and
            len(CURRENT_C08_HARDENING_CALLERS) == 57,
            "current C08 hardening: closed declaration/caller policy census differs")
    texts: dict[str, str] = {}
    codes: dict[str, str] = {}
    for relative in paths + support:
        path = ROOT / relative
        require(path.is_file(), f"current C08 hardening: missing source {relative}")
        texts[relative] = path.read_text(encoding="utf-8")
        if relative.endswith(".swift"):
            codes[relative] = _current_c08_swift_views(texts[relative])[1]
    logger_owner = "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift"
    for relative in paths:
        if not relative.endswith(".swift"):
            continue
        source = texts[relative]
        # Preserve the original complete raw prohibitions, including strings,
        # DEBUG/test branches and every scanned byte, not a token subset.
        require(re.search(r"\btry\s*!", source) is None,
                f"{relative}: force try is forbidden")
        require("preconditionFailure" not in source and "fatalError" not in source,
                f"{relative}: fail-stop primitive is forbidden")
        require(re.search(r"(?<![A-Za-z0-9_])MetricManager\b", source) is None
                and "CKRecord" not in source and "CloudKit" not in source
                and "URLSession" not in source,
                f"{relative}: forbidden remote/beta diagnostics dependency")
        if relative != logger_owner:
            # Exact standalone identity; DiagnosticsLogger is the existing
            # genuine sole adapter, not an exemption for a real Logger call.
            require(re.search(r"(?<![A-Za-z0-9_])Logger\s*\(", source) is None,
                    f"{relative}: direct Logger construction bypasses sole adapter")
            require(re.search(r"\bos_log\s*\(|\bOSSignposter\s*\(", source) is None,
                    f"{relative}: direct OS logging bypasses sole adapter")
        require(re.search(r"\bNSLog\s*\(|\bdebugPrint\s*\(", source) is None,
                f"{relative}: unregistered diagnostic output")
    frames = []
    expected: dict[tuple[str, str], list[int]] = {}
    for index, policy in enumerate(CURRENT_C08_HARDENING_DECLARATIONS):
        require(type(policy) is tuple and len(policy) == 10 and
                policy[0] in codes and type(policy[7]) is tuple,
                "current C08 hardening: declaration policy shape differs")
        relative, header = policy[:2]
        label = f"{relative} declaration {index} ({header.strip().splitlines()[0]})"
        start, end = _current_c08_hardening_frame(texts[relative], codes[relative], policy, label)
        frames.append((start, end))
        for kind, offset, conditions in policy[7]:
            require(kind in ("optionalTry", "print") and type(offset) is int,
                    "current C08 hardening: event policy shape differs")
            position = start + offset
            require(start <= position < end and
                    not codes[relative][position].isspace() and
                    _current_c08_hardening_conditions(codes[relative], position) == conditions,
                    f"current C08 hardening: {label} event scope/conditional differs")
            if kind == "print" and not relative.startswith("FieldEvidenceAppTests/"):
                require("if DEBUG" in conditions,
                        f"current C08 hardening: {label} production output is not DEBUG-owned")
            if relative.startswith("FieldEvidenceAppTests/") and kind == "print":
                require(any("XCTestCase" in owner or "extension S2PersistenceLedgerTests" in owner
                            for owner in policy[2]),
                        f"current C08 hardening: {label} diagnostic is not in its actual XCTest owner")
            expected.setdefault((relative, kind), []).append(position)
    # The historical sole-owner exception does not permit another logging
    # construction elsewhere in that file. Join the one genuine Logger site
    # to its complete pinned type AND its own zero-argument initializer.
    require(CURRENT_C08_HARDENING_DECLARATIONS[53][0] == logger_owner and
            CURRENT_C08_HARDENING_DECLARATIONS[53][1] ==
            "struct DiagnosticsLogger: Sendable {",
            "current C08 hardening: sole adapter declaration join differs")
    logger_start, logger_end = frames[53]
    logger_source, logger_code = texts[logger_owner], codes[logger_owner]
    block = logger_source[logger_start:logger_end]
    block_code = logger_code[logger_start:logger_end]
    initializer = _current_c08_code_matches(block, "    init() {", block_code)
    require(len(initializer) == 1,
            "current C08 hardening: sole adapter initializer identity differs")
    initializer_opening = initializer[0] + len("    init() {") - 1
    initializer_end = _current_c08_balanced_end(
        block_code, initializer_opening, "sole adapter initializer")
    constructor_position = logger_start + 326
    constructors = [match.start() for match in re.finditer(
        r"(?<![A-Za-z0-9_])Logger\s*\(", logger_source)]
    require(constructors == [constructor_position] and
            initializer_opening < 326 < initializer_end and
            logger_source.startswith("Logger(", constructor_position) and
            logger_code[constructor_position] == "L",
            "current C08 hardening: sole adapter constructor site/owner differs")
    require(re.search(r"\bos_log\s*\(|\bOSSignposter\s*\(", logger_source) is None,
            f"{logger_owner}: direct OS logging bypasses sole adapter")
    for relative in paths:
        if not relative.endswith(".swift"):
            continue
        for kind, pattern in (("optionalTry", r"\btry\s*\?"), ("print", r"\bprint\s*\(")):
            actual = [match.start() for match in re.finditer(pattern, texts[relative])]
            positions = expected.get((relative, kind), [])
            require(len(positions) == len(set(positions)) and sorted(positions) == actual,
                    f"current C08 hardening: unregistered/moved {kind} site: {relative}")
    require(sum(len(value) for (relative, kind), value in expected.items()
                if kind == "optionalTry") == 106 and
            sum(len(value) for (relative, kind), value in expected.items()
                if kind == "print") == 46,
            "current C08 hardening: complete current 106/46 event census differs")
    _current_c08_hardening_callers(texts, codes, frames)



def verify_source_bindings() -> None:
    contracts = [
        (system_health_contract(), "system health"),
        (lifecycle_contract(), "lifecycle"),
        (support_export_contract(), "support export"),
        (corpus_contract(), "corpus"),
    ]
    for document, name in contracts:
        for binding in document["sourceBindings"]:
            path = ROOT / binding["path"]
            if not path.is_file():
                require(binding["path"] in NEW_SOURCE_PATHS,
                        f"{name}: unexpected missing source {binding['path']}")
                continue
            text = path.read_text(encoding="utf-8")
            for token in binding["requiredTokens"]:
                if binding["path"] == NEW_SOURCE_PATHS[1] and not path.is_file():
                    continue
                if token in TEST_METHODS and not path.is_file():
                    continue
                require(token in text or binding["path"] == NEW_SOURCE_PATHS[2],
                        f"{name}: missing source token {token}: {binding['path']}")


def verify_source_hardening() -> None:
    swift_paths = [
        path for path in (EXISTING_PATHS + NEW_SOURCE_PATHS)
        if path.endswith(".swift") and (ROOT / path).is_file()
    ]
    optional_try_fragments = {
        "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift": (
            "fileIdentity(", "removeOwnedFile(", "syncDirectory(",
        ),
        "FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift": (
            "Self.sum(", "removeLeaseDirectory(",
        ),
        "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift": (
            "removeRegularFileIfExact(",
        ),
        NEW_SOURCE_PATHS[1]: ("FileManager.default.removeItem(",),
        "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift": ("removeItem(at:",),
        "FieldEvidenceAppTests/S2PersistenceLedgerTests.swift": ("removeItem(at:",),
    }
    logger_owner = "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift"
    for relative in swift_paths:
        text = (ROOT / relative).read_text(encoding="utf-8")
        require("try!" not in text, f"{relative}: force try is forbidden")
        require("preconditionFailure" not in text and "fatalError" not in text,
                f"{relative}: fail-stop primitive is forbidden")
        require(re.search(r"(?<![A-Za-z0-9_])MetricManager\b", text) is None
                and "CKRecord" not in text
                and "CloudKit" not in text and "URLSession" not in text,
                f"{relative}: forbidden remote/beta diagnostics dependency")
        for line in text.splitlines():
            if "try?" in line:
                allowed = optional_try_fragments.get(relative, ())
                require(any(fragment in line for fragment in allowed),
                        f"{relative}: operational try? is not an approved cleanup/fail-closed path")
        if relative != logger_owner:
            require("Logger(" not in text, f"{relative}: direct Logger construction bypasses sole adapter")
            require("os_log(" not in text and "OSSignposter(" not in text,
                    f"{relative}: direct OS logging bypasses sole adapter")
        require("NSLog(" not in text and "debugPrint(" not in text and "print(" not in text,
                f"{relative}: unregistered diagnostic output")


def verify_fixture_hostility() -> None:
    original = system_health_contract()
    hostile = copy.deepcopy(original)
    hostile["metricSource"]["activeSourceCount"] = 2
    require(hostile != original, "hostile mutation was inert")
    try:
        validate_instance(hostile, load(SYSTEM_HEALTH_SCHEMA), "hostile metric source")
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile duplicate MetricKit source accepted")

    hostile = copy.deepcopy(support_export_contract())
    hostile["bundle"]["allowlist"].append("customerNote")
    try:
        validate_instance(hostile, load(SUPPORT_EXPORT_SCHEMA), "hostile export allowlist")
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile customer field accepted")

    hostile = copy.deepcopy(lifecycle_contract())
    hostile["scratch"]["bounds"][0]["maximumBytes"] = 2
    try:
        validate_instance(hostile, load(OPERATIONAL_FAILURE_SCHEMA), "hostile scratch bound")
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile scratch bound accepted")

    hostile = copy.deepcopy(system_health_contract())
    hostile["workflowFriction"]["defaultEnabled"] = True
    try:
        validate_instance(hostile, load(SYSTEM_HEALTH_SCHEMA), "hostile friction")
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile friction enablement accepted")


def verify_scripts_parse() -> None:
    for relative in (CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT):
        source = (ROOT / relative).read_text(encoding="utf-8")
        try:
            ast.parse(source, filename=relative)
        except SyntaxError as error:
            raise VerificationError(f"{relative}: syntax error: {error}") from error


def verify_generator_check() -> None:
    result = subprocess.run(
        [sys.executable, "-B", str(ROOT / GENERATOR_SCRIPT), "--check", "--root", str(ROOT)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    require(result.returncode == 0, f"generator --check failed: {result.stdout}{result.stderr}")


def main() -> int:
    try:
        verify_scripts_parse()
        verify_generated()
        for relative in (
            SYSTEM_HEALTH_SCHEMA, OPERATIONAL_FAILURE_SCHEMA,
            WORKFLOW_FRICTION_SCHEMA, SUPPORT_EXPORT_SCHEMA,
        ):
            verify_strict_schema(load(relative), relative)
        verify_health(load(SYSTEM_HEALTH_DOC))
        verify_lifecycle(load(LIFECYCLE_DOC))
        verify_export(load(SUPPORT_EXPORT_DOC))
        verify_corpus(load(CORPUS_DOC))
        verify_manifest()
        verify_source_bindings()
        verify_source_hardening()
        verify_fixture_hostility()
        verify_generator_check()
    except VerificationError as error:
        print(f"FAIL Card28 hostile static verification: {error}", file=sys.stderr)
        return 1
    manifest = load(MANIFEST)
    print(
        "V23-P02-C08 hostile static verification passed: "
        f"{manifest['pathFenceCount']} fence paths, {manifest['artifactCount']} sealed inputs, "
        "4 strict schemas, 5 evidence tests"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

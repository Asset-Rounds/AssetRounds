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

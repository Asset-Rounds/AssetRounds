#!/usr/bin/env python3
"""Static, source-bound, and hostile verification for V23-P01-C03 tooling."""
from __future__ import annotations

import argparse
import ast
import copy
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from p01_c03_contracts import *


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def verify_digest(value: dict[str, Any]) -> None:
    body = {key: item for key, item in value.items() if key != "artifactDigest"}
    if value.get("artifactDigest") != sha(pretty(body)):
        raise ContractError("sealed artifact digest differs")


def validate_schema(value: Any, schema_value: dict[str, Any], where: str = "$") -> None:
    if "const" in schema_value and value != schema_value["const"]:
        raise ContractError(f"{where}: const")
    schema_type = schema_value.get("type")
    types = {
        "object": dict,
        "array": list,
        "string": str,
        "integer": int,
        "boolean": bool,
        "null": type(None),
    }
    if schema_type and (
        not isinstance(value, types[schema_type])
        or schema_type == "integer"
        and isinstance(value, bool)
    ):
        raise ContractError(f"{where}: type")
    if isinstance(value, dict):
        properties = schema_value.get("properties", {})
        missing = set(schema_value.get("required", [])) - set(value)
        extra = set(value) - set(properties)
        if missing or (schema_value.get("additionalProperties") is False and extra):
            raise ContractError(f"{where}: shape")
        for key, item in value.items():
            if key in properties:
                validate_schema(item, properties[key], f"{where}.{key}")
    if isinstance(value, list):
        if len(value) < schema_value.get("minItems", 0) or len(value) > schema_value.get(
            "maxItems", sys.maxsize
        ):
            raise ContractError(f"{where}: count")
        for index, item_schema in enumerate(schema_value.get("prefixItems", [])):
            validate_schema(value[index], item_schema, f"{where}[{index}]")
    if isinstance(value, str):
        if len(value) < schema_value.get("minLength", 0):
            raise ContractError(f"{where}: short string")
        if "pattern" in schema_value and re.fullmatch(schema_value["pattern"], value) is None:
            raise ContractError(f"{where}: string pattern")


def reject(callback: Any) -> None:
    try:
        callback()
    except (ContractError, IndexError, KeyError, TypeError, ValueError):
        return
    raise ContractError("hostile mutation passed")


def mutate(value: dict[str, Any], path: tuple[Any, ...], replacement: Any) -> dict[str, Any]:
    result = copy.deepcopy(value)
    target: Any = result
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = replacement
    return result


def source_check(root: Path, migration_value: dict[str, Any]) -> dict[str, int | bool]:
    expected = source_bindings(root)
    if migration_value.get("sourceBindings") != expected:
        raise ContractError("stale source bindings")
    if migration_value.get("sourceBindingCount") != len(SOURCE_PATHS):
        raise ContractError("source binding count")
    for row, (_, required_symbols) in zip(migration_value["sourceBindings"], SOURCE_SPECS):
        path = root / row["path"]
        if row["status"] != "BOUND":
            raise ContractError("unbound source")
        text = path.read_text(encoding="utf-8")
        if sha(path.read_bytes()) != row["sha256"] or path.stat().st_size != row["bytes"]:
            raise ContractError(f"source digest differs: {row['path']}")
        if row["requiredSymbols"] != required_symbols or any(
            symbol not in text for symbol in required_symbols
        ):
            raise ContractError(f"source symbol evidence differs: {row['path']}")
    return {
        "sourceBindingCount": len(SOURCE_PATHS),
        "boundSourceCount": len(migration_value["sourceBindings"]),
        "sourceBindingComplete": migration_value["sourceBindingComplete"],
    }


def claims_check(root: Path, value: dict[str, Any]) -> None:
    if value.get("claims") != claims() or value.get("hostileChecks") != hostile_checks():
        raise ContractError("claims or hostile checks differ")
    claim_ids = {claim["id"] for claim in value["claims"]}
    if claim_ids != {
        "PREPARED_ENVELOPE",
        "BOUNDED_STREAMING_SOURCE_REPROOF",
        "POINTER_SWAP_TEMP_RECONCILIATION",
        "PHASE_AWARE_ENOSPC_PROTECTED_CLASSIFICATION",
        "DEBUG_ONLY_FAULT_INJECTION",
    }:
        raise ContractError("claim set")
    for claim in value["claims"]:
        if claim["status"] != "SOURCE_BOUND_BEHAVIORAL_CLAIM_NOT_ACCEPTANCE":
            raise ContractError("claim overclaim")
        for requirement in claim["sourceRequirements"]:
            path = root / requirement["path"]
            text = path.read_text(encoding="utf-8")
            if any(symbol not in text for symbol in requirement["requiredSymbols"]):
                raise ContractError(f"claim source symbol missing: {path}")
    if [item["claimID"] for item in value["hostileChecks"]] != [
        "PREPARED_ENVELOPE",
        "BOUNDED_STREAMING_SOURCE_REPROOF",
        "BOUNDED_STREAMING_SOURCE_REPROOF",
        "BOUNDED_STREAMING_SOURCE_REPROOF",
        "POINTER_SWAP_TEMP_RECONCILIATION",
        "PHASE_AWARE_ENOSPC_PROTECTED_CLASSIFICATION",
        "DEBUG_ONLY_FAULT_INJECTION",
    ]:
        raise ContractError("hostile claim coverage")


def current(root: Path, migration_value: dict[str, Any], registry_value: dict[str, Any]) -> None:
    if migration_value != migration(root) or registry_value != registry(root):
        raise ContractError("generated semantic output differs")
    expected_authority = authority()
    if migration_value["authority"] != expected_authority or registry_value["authority"] != expected_authority:
        raise ContractError("authority differs")
    if FULL_FENCE != SOURCE_PATHS + TOOL_PATHS or len(FULL_FENCE) != 15:
        raise ContractError("exact 15-path fence")
    if len(set(FULL_FENCE)) != 15 or migration_value["fullPathFence"] != FULL_FENCE:
        raise ContractError("duplicate or stale full fence")
    if registry_value["sourceBindings"] != migration_value["sourceBindings"]:
        raise ContractError("registry source binding drift")

    if migration_value["schemaTransition"] != {
        "source": "PersistentSchemaV1",
        "sourceVersion": [1, 0, 0],
        "target": "PersistentSchemaV2",
        "targetVersion": TARGET_VERSION,
        "targetStatus": "V2_ACTIVE",
    }:
        raise ContractError("schema transition")
    if migration_value["pointerTransition"] != {
        "sourceFormat": 1,
        "targetFormat": 2,
        "publicationPhase": "pointerPublished",
        "soleActivationBoundary": True,
    }:
        raise ContractError("pointer transition")
    if migration_value["migrationPhases"] != PHASES:
        raise ContractError("migration phases")
    if migration_value["faultClasses"] != FAILURE_CLASSES or migration_value["faultBoundaries"] != FAULT_BOUNDARIES:
        raise ContractError("fault declarations")

    if len(migration_value["faultMatrix"]) != len(PHASES) * len(FAULTS):
        raise ContractError("fault matrix count")
    publication_index = PHASES.index("pointerPublished")
    for row in migration_value["faultMatrix"]:
        published = PHASES.index(row["phase"]) >= publication_index
        expected_recovery = (
            "RETAIN_EVIDENCE_AND_FORWARD_FIX_V2_NEVER_REOPEN_V1"
            if published
            else "DISCARD_STAGING_KEEP_IMMUTABLE_V1_ACTIVE"
        )
        if (
            row["publicationBoundaryCrossed"] != published
            or row["requiredRecovery"] != expected_recovery
            or row["result"] != "NOT_RUN"
        ):
            raise ContractError("fault matrix row")
    if len(migration_value["faultBoundaryMatrix"]) != len(FAULT_BOUNDARIES):
        raise ContractError("fault boundary matrix count")
    for index, row in enumerate(migration_value["faultBoundaryMatrix"]):
        phase_index = min(len(PHASES) - 1, index // 2)
        published = phase_index >= publication_index
        expected_recovery = (
            "RETAIN_EVIDENCE_AND_FORWARD_FIX_V2_NEVER_REOPEN_V1"
            if published
            else "DISCARD_STAGING_KEEP_IMMUTABLE_V1_ACTIVE"
        )
        if (
            row["boundary"] != FAULT_BOUNDARIES[index]
            or row["phase"] != PHASES[phase_index]
            or row["publicationBoundaryCrossed"] != published
            or row["requiredRecovery"] != expected_recovery
            or row["result"] != "NOT_RUN"
        ):
            raise ContractError("fault boundary row")

    expected_identity = identity_intent()
    if migration_value["identityIntent"] != expected_identity or registry_value["identityIntent"] != expected_identity:
        raise ContractError("identity intent")
    if migration_value["frozenIntent"] != frozen_intent() or registry_value["frozenIntent"] != frozen_intent():
        raise ContractError("frozen identity intent")
    if migration_value["semanticDigestPolicy"] != semantic_digest_policy() or registry_value["semanticDigestPolicy"] != semantic_digest_policy():
        raise ContractError("semantic digest policy")
    if migration_value["semanticDigestPolicy"]["preparedSourceManifestSemanticSHA256"] != "OPTIONAL_NIL_BEFORE_SOURCE_CLONE":
        raise ContractError("prepared semantic digest overclaim")
    if not migration_value["semanticDigestPolicy"]["v2TargetComparedToJournalSourceSemanticDigest"]:
        raise ContractError("target semantic comparison")

    claims_check(root, migration_value)
    claims_check(root, registry_value)
    boundary = migration_value["forwardOnlyBoundary"]
    if boundary["inPlaceAcceptedStoreMutation"] or boundary["automaticDestructiveRecovery"]:
        raise ContractError("destructive recovery")

    rows = registry_value["releaseRows"]
    if [row["concreteVersion"] for row in rows] != [[1, 0, 0], TARGET_VERSION]:
        raise ContractError("release versions")
    if rows[0]["predecessor"] != "NONE" or rows[1]["predecessor"] != "PRE_LOCATION_STORE_V1":
        raise ContractError("release predecessor")
    if rows[1]["markerID"] != MARKER_ID or registry_value["activeSchema"] != "PRE_LOCATION_STORE_V2":
        raise ContractError("release marker or active schema")
    if registry_value["acceptedS10_6SeedDigest"] is not None or "PENDING_ACCEPTED_S10_6_PREV21_COMPATIBILITY_SEED" not in registry_value["blockers"]:
        raise ContractError("seed fabrication")

    false_flags = (
        "nativeCompileRan",
        "hostedDispatchRan",
        "physicalEvidenceComplete",
        "adoptionEnabled",
        "acceptanceEnabled",
        "acceptanceCredit",
        "releaseReady",
        "releaseCredit",
        "phase10PollingDuringParallelExecution",
    )
    for value in (migration_value, registry_value):
        if any(value[key] for key in false_flags):
            raise ContractError("verification or release overclaim")
        if value["acceptedS10_6Blocker"] is not True:
            raise ContractError("accepted S10 blocker was cleared")
        if value["physicalLockedState"] != "REQUIRED_PENDING_OWNER":
            raise ContractError("physical state overclaim")
        if not value["requiresAcceptedS10_6Reconciliation"]:
            raise ContractError("accepted S10 reconciliation overclaim")


def hostile_mutations(root: Path, migration_value: dict[str, Any], registry_value: dict[str, Any]) -> int:
    count = 0
    migration_cases = [
        (("authority", "contextDigest"), "0" * 64),
        (("authority", "coordinationAuthorityHead"), "0" * 40),
        (("authority", "coordinationCASSequence"), 61),
        (("authority", "coordinationLedgerDigest"), "0" * 64),
        (("authority", "hydrationCorrectionReceiptDigest"), "0" * 64),
        (("authority", "pathFenceDigest"), "0" * 64),
        (("fullPathFence",), FULL_FENCE[:-1]),
        (("sourceBindingCount",), 6),
        (("sourceBindingComplete",), False),
        (("schemaTransition", "targetStatus"), "DORMANT"),
        (("schemaTransition", "sourceVersion"), [2, 0, 0]),
        (("pointerTransition", "sourceFormat"), 2),
        (("pointerTransition", "targetFormat"), 1),
        (("pointerTransition", "soleActivationBoundary"), False),
        (("migrationPhases",), PHASES[:-1]),
        (("faultBoundaries",), FAULT_BOUNDARIES[:-1]),
        (("faultMatrix",), migration_value["faultMatrix"][:-1]),
        (("faultBoundaryMatrix",), migration_value["faultBoundaryMatrix"][:-1]),
        (("frozenIntent", "generatedWorkspaceIDCount"), 1),
        (("frozenIntent", "generatedReplicaIDCount"), 1),
        (("frozenIntent", "existingIDsPreservedByCanonicalSemanticEquality"), False),
        (("frozenIntent", "frozenMarkerID"), "0" * 36),
        (("identityIntent", "generatedByV1ToV2"), True),
        (("identityIntent", "canonicalSourceTargetSemanticEquality"), False),
        (("identityIntent", "frozenValues", "markerID"), "0" * 36),
        (("identityIntent", "frozenValues", "targetVersion"), [3, 0, 0]),
        (("semanticDigestPolicy", "preparedSourceManifestSemanticSHA256"), "REQUIRED"),
        (("semanticDigestPolicy", "v2TargetComparedToJournalSourceSemanticDigest"), False),
        (("claims",), migration_value["claims"][:-1]),
        (("hostileChecks",), migration_value["hostileChecks"][:-1]),
        (("forwardOnlyBoundary", "beforePublication"), "MUTATE_V1"),
        (("forwardOnlyBoundary", "atOrAfterPublicationOrPossibleV2Write"), "REOPEN_V1"),
        (("forwardOnlyBoundary", "inPlaceAcceptedStoreMutation"), True),
        (("forwardOnlyBoundary", "automaticDestructiveRecovery"), True),
        (("acceptedS10_6Blocker",), False),
        (("nativeCompileRan",), True),
        (("physicalEvidenceComplete",), True),
        (("acceptanceCredit",), True),
        (("releaseReady",), True),
    ]
    for path, replacement in migration_cases:
        reject(lambda path=path, replacement=replacement: current(root, mutate(migration_value, path, replacement), registry_value))
        count += 1

    registry_cases = [
        (("sourceBindingCount",), 6),
        (("releaseRows", 1, "predecessor"), "NONE"),
        (("releaseRows", 1, "concreteVersion"), [3, 0, 0]),
        (("releaseRows", 1, "markerID"), "0" * 36),
        (("registryLaws", "duplicateSuccessorRejected"), False),
        (("registryLaws", "frozenIdentityBeforeConversion"), False),
        (("activeSchema",), "PRE_LOCATION_STORE_V1"),
        (("acceptedS10_6SeedDigest",), "0" * 64),
        (("blockers",), []),
        (("identityIntent", "generatedReplicaIDCount"), 1),
        (("semanticDigestPolicy", "preparedSourceManifestSemanticSHA256"), "REQUIRED"),
        (("acceptanceCredit",), True),
        (("releaseCredit",), True),
    ]
    for path, replacement in registry_cases:
        reject(lambda path=path, replacement=replacement: current(root, migration_value, mutate(registry_value, path, replacement)))
        count += 1

    extra = copy.deepcopy(migration_value)
    extra["extra"] = 1
    reject(lambda: validate_schema(extra, load(root / MIGRATION_SCHEMA)))
    count += 1
    bad = copy.deepcopy(registry_value)
    bad["artifactDigest"] = "0" * 64
    reject(lambda: verify_digest(bad))
    count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    args = parser.parse_args()
    root = args.root.resolve()
    checks = 0

    expected = outputs(root)
    for relative, value in expected.items():
        path = root / relative
        if not path.is_file() or path.read_bytes() != pretty(value):
            raise ContractError(f"generated differs: {relative}")
        checks += 1

    migration_value = load(root / MIGRATION_ARTIFACT)
    registry_value = load(root / REGISTRY_ARTIFACT)
    migration_schema = load(root / MIGRATION_SCHEMA)
    registry_schema = load(root / REGISTRY_SCHEMA)
    validate_schema(migration_value, migration_schema)
    validate_schema(registry_value, registry_schema)
    verify_digest(migration_value)
    verify_digest(registry_value)
    current(root, migration_value, registry_value)
    counts = source_check(root, migration_value)
    checks += 4

    for path in TOOL_PATHS[:3]:
        ast.parse((root / path).read_text(encoding="utf-8"), filename=path)
        checks += 1

    hostile_count = hostile_mutations(root, migration_value, registry_value)
    checks += hostile_count

    manifest_value = load(root / MANIFEST)
    if manifest_value != manifest(root):
        raise ContractError("tooling manifest differs")
    if manifest_value["artifactCount"] != 7 or manifest_value["pathFence"] != TOOL_PATHS or manifest_value["fullCardFence"] != FULL_FENCE:
        raise ContractError("manifest fence")
    verify_digest(manifest_value)
    checks += 4

    run = subprocess.run(
        [
            sys.executable,
            "-B",
            str(root / "Scripts/v23/generate_p01_c03_contracts.py"),
            "--check",
            "--root",
            str(root),
        ],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    if "PASS V23-P01-C03 generated=5 check=True" not in run.stdout:
        raise ContractError("generator check")
    checks += 1

    print(
        json.dumps(
            {
                "result": "PASS",
                "cardID": CARD,
                "checks": checks,
                "hostileMutationCount": hostile_count,
                "pathFenceCount": len(FULL_FENCE),
                "sourceBindingCount": len(SOURCE_PATHS),
                "phaseCount": len(PHASES),
                "faultMatrixCount": len(PHASES) * len(FAULTS),
                "faultBoundaryCount": len(FAULT_BOUNDARIES),
                "schemaReleaseCount": 2,
                "nativeCompileRan": False,
                "hostedDispatchRan": False,
                "physicalEvidenceComplete": False,
                "acceptanceCredit": False,
                "releaseCredit": False,
                "acceptedS10_6Blocker": True,
                "phase10PollingDuringParallelExecution": False,
                "requiresAcceptedS10_6Reconciliation": True,
                **counts,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

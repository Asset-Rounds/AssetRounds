#!/usr/bin/env python3
"""Verify V23-P00-C11 contracts and hostile concurrency cases."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

from c07_contracts import digest, sha256_bytes
from c11_contracts import (
    ARTIFACT_PATHS,
    CARD_ID,
    FENCED_PATHS,
    MANIFEST_PATH,
    SCHEMA_PATHS,
    ContractError,
    build_manifest,
    build_outputs,
    pretty_bytes,
    validate_swift_delta,
)
from verify_c07_contracts import validate_schema, verify_digest


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def expect_failure(callable_value) -> None:
    try:
        callable_value()
    except (ContractError, ValueError):
        return
    raise ContractError("hostile C11 case did not fail")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    schemas, artifacts = build_outputs(root)
    checks = 0
    for relative, expected in {**schemas, **artifacts}.items():
        path = root / relative
        if not path.is_file() or path.read_bytes() != pretty_bytes(expected):
            raise ContractError(f"generated C11 output differs: {relative}")
        checks += 1
    for schema_path, artifact_path in zip(SCHEMA_PATHS, ARTIFACT_PATHS, strict=True):
        schema = load(root / schema_path)
        artifact = load(root / artifact_path)
        validate_schema(artifact, schema)
        verify_digest(artifact)
        checks += 2
        unknown = copy.deepcopy(artifact)
        unknown["unknown"] = True
        expect_failure(lambda value=unknown, contract=schema: validate_schema(value, contract))
        corrupt = copy.deepcopy(artifact)
        corrupt["cardID"] = "V23-P00-C99"
        expect_failure(lambda value=corrupt, contract=schema: validate_schema(value, contract))
        checks += 2
    inventory, unsafe, ports, closure, migration, platform = [load(root / path) for path in ARTIFACT_PATHS]
    if inventory["newForbiddenDebtCount"] != 0:
        raise ContractError("C11 introduced forbidden concurrency debt")
    if unsafe["newUncheckedCount"] or unsafe["newUnsafeIsolationCount"] or unsafe["newDetachedTaskCount"] or unsafe["newPreconcurrencyCount"]:
        raise ContractError("C11 hostile unsafe-boundary ratchet differs")
    if unsafe["ownedAssumeIsolatedCount"] != 1:
        raise ContractError("C11 must own exactly one tested Mail actor assertion")
    checks += 3
    dependencies = {row["dependency"]: row for row in ports["ports"]}
    if dependencies["RANDOM"]["status"] != "NOT_APPLICABLE_NO_PRODUCTION_RANDOM_CALLSITE":
        raise ContractError("C11 invented or omitted random-source disposition")
    if dependencies["ASYNC_DELAY"]["status"] != "IMPLEMENTED_CANCELLATION_PRESERVING_AND_FAILURE_PROPAGATING":
        raise ContractError("C11 deterministic async port disposition differs")
    if ports["candidateDirectDependencyCounts"]["randomSource"] != 0:
        raise ContractError("random-source N/A disposition is stale")
    checks += 3
    if platform["mailBoundary"]["terminalOutcomes"] != ["cancelled", "failed", "saved", "sent"]:
        raise ContractError("Mail outcome matrix differs")
    if platform["mailBoundary"]["messageUIValuesCrossActorBoundary"] or platform["mailBoundary"]["unstructuredTaskCreated"]:
        raise ContractError("Mail adapter crosses non-Sendable values or creates unstructured task")
    if not platform["systemAsyncBoundary"]["cancellationPreserved"] or not platform["systemAsyncBoundary"]["nonCancellationErrorsPropagate"]:
        raise ContractError("system async failure semantics differ")
    checks += 3
    if closure["closureSatisfied"] or closure["swift5CompleteZeroWarningStatus"] != "NOT_RUN_RESERVED_PROJECT_AND_HOSTED_WORKFLOW":
        raise ContractError("C11 closure receipt overclaims native closure")
    if closure["staticContractStatus"] != "PASS" or closure["c07AllocatedClauseCount"] != 10:
        raise ContractError("C11 static closure or C07 allocation differs")
    if migration["languageModeChangedByC11"] or not migration["writerTruthPreserved"]:
        raise ContractError("C11 migration plan changes language mode or writer truth")
    checks += 3
    authorities = [value["authority"] for value in (inventory, unsafe, ports, closure, migration, platform)]
    if any(value != authorities[0] for value in authorities[1:]):
        raise ContractError("C11 cross-artifact authority differs")
    if any(authorities[0][key] for key in (
        "phase10PollingDuringParallelExecution", "acceptanceEnabled", "hostedDispatchEnabled", "adoptionEnabled", "releaseCredit"
    )):
        raise ContractError("C11 provisional authority enables forbidden capability")
    checks += 2
    expected_cross = {
        "isolationInventoryDigest": inventory["artifactDigest"],
        "unsafeDispositionDigest": unsafe["artifactDigest"],
        "deterministicAsyncPortDigest": ports["artifactDigest"],
        "migrationPlanDigest": migration["artifactDigest"],
        "platformAdapterDigest": platform["artifactDigest"],
    }
    if any(closure[key] != value for key, value in expected_cross.items()):
        raise ContractError("C11 closure cross-artifact digest differs")
    checks += 1
    validate_swift_delta(root)
    checks += 1
    manifest = load(root / MANIFEST_PATH)
    if manifest != build_manifest(root):
        raise ContractError("C11 manifest differs")
    verify_digest(manifest)
    if manifest["pathFence"] != FENCED_PATHS or manifest["artifactCount"] != len(FENCED_PATHS) - 1:
        raise ContractError("C11 manifest fence differs")
    if [row["path"] for row in manifest["artifacts"]] != [path for path in FENCED_PATHS if path != MANIFEST_PATH]:
        raise ContractError("C11 manifest artifact order differs")
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"C11 manifest hash differs: {row['path']}")
    checks += 3
    completed = subprocess.run(
        [sys.executable, "-B", str(root / "Scripts/v23/generate_c11_contracts.py"), "--check", "--root", str(root)],
        check=True,
        capture_output=True,
        text=True,
        env={**__import__("os").environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    if "PASS V23-P00-C11" not in completed.stdout:
        raise ContractError("C11 deterministic generator check failed")
    checks += 1
    print(json.dumps({
        "result": "PASS",
        "cardID": CARD_ID,
        "checks": checks,
        "productionSwiftFileCount": inventory["candidate"]["productionSwiftFileCount"],
        "uncheckedBoundaryCount": unsafe["candidateUncheckedCount"],
        "ownedAssumeIsolatedCount": unsafe["ownedAssumeIsolatedCount"],
        "deterministicPortCount": len(ports["ports"]),
        "nativeCompileRan": False,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Verify V23-P00-C12 static closure preparation and hostile cases."""

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
from pathlib import Path

from c07_contracts import sha256_bytes
from c12_contracts import (
    ARTIFACT_PATH,
    BASE_HEAD,
    CARD_ID,
    FENCED_PATHS,
    MANIFEST_PATH,
    PROJECT_PATH,
    SCHEMA_PATH,
    ContractError,
    build_manifest,
    build_outputs,
    load_reservation,
    prerequisite_bindings,
    pretty_bytes,
    target_matrix,
    validate_receipt_semantics,
)
from verify_c07_contracts import validate_schema, verify_digest


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def expect_failure(callable_value) -> None:
    try:
        callable_value()
    except (ContractError, ValueError):
        return
    raise ContractError("hostile C12 case did not fail")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    outputs = build_outputs(root)
    checks = 0
    for relative, expected in outputs.items():
        path = root / relative
        if not path.is_file() or path.read_bytes() != pretty_bytes(expected):
            raise ContractError(f"generated C12 output differs: {relative}")
        checks += 1
    schema = load(root / SCHEMA_PATH)
    receipt = load(root / ARTIFACT_PATH)
    validate_schema(receipt, schema)
    verify_digest(receipt)
    checks += 2
    matrix = target_matrix(root)
    if matrix != receipt["targetConfigurationMatrix"] or len(matrix) != 6:
        raise ContractError("C12 target/configuration matrix differs")
    if {row["target"] for row in matrix} != {"FieldEvidenceApp", "FieldEvidenceAppTests", "FieldEvidenceAppUITests"}:
        raise ContractError("C12 target set differs")
    if {row["configuration"] for row in matrix} != {"Debug", "Release"}:
        raise ContractError("C12 configuration set differs")
    checks += 3
    reservation = load_reservation(root)
    prerequisites = prerequisite_bindings(root)
    validate_receipt_semantics(receipt, reservation, prerequisites)
    if receipt["project"]["sha256"] != sha256_bytes((root / PROJECT_PATH).read_bytes()):
        raise ContractError("C12 project source digest differs")
    if receipt["staticPreparationStatus"] != "PASS_EXACT_SIX_CONFIGURATION_GAP_INVENTORIED":
        raise ContractError("C12 static preparation status differs")
    checks += 3
    unknown = copy.deepcopy(receipt)
    unknown["unknown"] = True
    expect_failure(lambda: validate_schema(unknown, schema))
    stale = copy.deepcopy(receipt)
    stale["authority"]["baseHead"] = "0" * 40
    expect_failure(lambda: validate_schema(stale, schema))
    missing = copy.deepcopy(receipt)
    missing["targetConfigurationMatrix"].pop()
    expect_failure(lambda: validate_receipt_semantics(missing, reservation, prerequisites))
    checks += 3
    changed_prerequisite = copy.deepcopy(receipt)
    changed_prerequisite["prerequisiteBindings"]["C11PlatformAdapterDigest"] = "0" * 64
    expect_failure(lambda: validate_receipt_semantics(changed_prerequisite, reservation, prerequisites))
    unsafe_growth = copy.deepcopy(receipt)
    unsafe_growth["unsafeBoundaryRatchet"]["candidateCounts"]["uncheckedSendable"] += 1
    expect_failure(lambda: validate_receipt_semantics(unsafe_growth, reservation, prerequisites))
    overclaim = copy.deepcopy(receipt)
    overclaim["languageModeClosureSatisfied"] = True
    expect_failure(lambda: validate_receipt_semantics(overclaim, reservation, prerequisites))
    checks += 3
    overlap_reservation = copy.deepcopy(reservation)
    overlap_reservation["reservedPaths"] = [*overlap_reservation["reservedPaths"], FENCED_PATHS[0]]
    expect_failure(lambda: validate_receipt_semantics(receipt, overlap_reservation, prerequisites))
    missing_reserved = copy.deepcopy(reservation)
    missing_reserved["reservedPaths"] = [path for path in missing_reserved["reservedPaths"] if path != PROJECT_PATH]
    expect_failure(lambda: validate_receipt_semantics(receipt, missing_reserved, prerequisites))
    checks += 2
    manifest = load(root / MANIFEST_PATH)
    if manifest != build_manifest(root):
        raise ContractError("C12 manifest differs")
    verify_digest(manifest)
    if manifest["pathFence"] != FENCED_PATHS or manifest["artifactCount"] != 5:
        raise ContractError("C12 manifest fence differs")
    if [row["path"] for row in manifest["artifacts"]] != [path for path in FENCED_PATHS if path != MANIFEST_PATH]:
        raise ContractError("C12 manifest artifact order differs")
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"C12 manifest hash differs: {row['path']}")
    checks += 3
    completed = subprocess.run(
        [sys.executable, "-B", str(root / "Scripts/v23/generate_c12_contracts.py"), "--check", "--root", str(root)],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    if "PASS V23-P00-C12" not in completed.stdout:
        raise ContractError("C12 deterministic generator check failed")
    checks += 1
    print(json.dumps({
        "result": "PASS",
        "cardID": CARD_ID,
        "checks": checks,
        "targetCount": receipt["project"]["targetCount"],
        "targetConfigurationCount": receipt["project"]["targetConfigurationCount"],
        "currentSwift5ConfigurationCount": receipt["project"]["currentSwiftVersionSettingCount"],
        "nativeCompileRan": False,
        "languageModeClosureSatisfied": False,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

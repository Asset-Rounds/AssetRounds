#!/usr/bin/env python3
"""Verify V23-P00-C07 contracts and hostile reference-model cases."""

from __future__ import annotations

import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from c07_contracts import (
    CARD_ID,
    CLOSURE_MEMBERS,
    EXPECTED_ATOMIC_IDS,
    FENCED_PATHS,
    MANIFEST_PATH,
    OUTPUT_PATHS,
    RESERVATION,
    RESERVATION_DIGEST,
    ContractError,
    build_manifest,
    build_outputs,
    digest,
    model_test_root,
    pretty_bytes,
    sha256_bytes,
)


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_schema(value: Any, schema: dict[str, Any], where: str = "$") -> None:
    if "const" in schema and value != schema["const"]:
        raise ContractError(f"{where}: const mismatch")
    if "enum" in schema and value not in schema["enum"]:
        raise ContractError(f"{where}: enum mismatch")
    expected_type = schema.get("type")
    type_map = {"object": dict, "array": list, "string": str, "integer": int, "boolean": bool, "null": type(None)}
    if expected_type:
        expected = type_map[expected_type]
        if not isinstance(value, expected) or (expected_type == "integer" and isinstance(value, bool)):
            raise ContractError(f"{where}: expected {expected_type}")
    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [key for key in required if key not in value]
        if missing:
            raise ContractError(f"{where}: missing {missing}")
        properties = schema.get("properties", {})
        additional = schema.get("additionalProperties", True)
        if additional is False:
            extras = set(value) - set(properties)
            if extras:
                raise ContractError(f"{where}: extra keys {sorted(extras)}")
        for key, item in value.items():
            if key in properties:
                validate_schema(item, properties[key], f"{where}.{key}")
            elif isinstance(additional, dict):
                validate_schema(item, additional, f"{where}.{key}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0) or len(value) > schema.get("maxItems", sys.maxsize):
            raise ContractError(f"{where}: item count")
        if schema.get("uniqueItems") and len({json.dumps(item, sort_keys=True) for item in value}) != len(value):
            raise ContractError(f"{where}: duplicate items")
        item_schema = schema.get("items")
        if item_schema:
            for index, item in enumerate(value):
                validate_schema(item, item_schema, f"{where}[{index}]")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise ContractError(f"{where}: string too short")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            raise ContractError(f"{where}: pattern mismatch")
    if isinstance(value, int) and not isinstance(value, bool) and value < schema.get("minimum", value):
        raise ContractError(f"{where}: below minimum")


def verify_digest(value: dict[str, Any], field: str = "artifactDigest") -> None:
    body = {key: item for key, item in value.items() if key != field}
    if value.get(field) != digest(body):
        raise ContractError(f"{value.get('schema')}: digest mismatch")


def expect_error(callable_value: Any) -> None:
    try:
        callable_value()
    except ContractError:
        return
    raise ContractError("hostile path case did not fail")


def expect_contract_error(callable_value: Any) -> None:
    try:
        callable_value()
    except ContractError:
        return
    raise ContractError("hostile contract case did not fail")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    expected = build_outputs(root)
    checks = 0
    for relative, expected_value in expected.items():
        path = root / relative
        if not path.is_file() or path.read_bytes() != pretty_bytes(expected_value):
            raise ContractError(f"generated output differs: {relative}")
        checks += 1
    for schema_path in OUTPUT_PATHS[:6]:
        schema = load(root / schema_path)
        artifact_path = OUTPUT_PATHS[6 + OUTPUT_PATHS[:6].index(schema_path)]
        artifact = load(root / artifact_path)
        validate_schema(artifact, schema)
        verify_digest(artifact)
        checks += 2
    artifacts = [load(root / relative) for relative in OUTPUT_PATHS[6:]]
    first_authority = artifacts[0]["authority"]
    if any(artifact["authority"] != first_authority for artifact in artifacts[1:]):
        raise ContractError("cross-artifact authority binding differs")
    if first_authority["ledgerCASSequence"] != 19 or first_authority["writerAuthority"] != {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0}:
        raise ContractError("writer authority or ledger CAS differs")
    for forbidden_true in ("phase10PollingDuringParallelExecution", "acceptanceEnabled", "hostedDispatchEnabled", "adoptionEnabled", "releaseCredit"):
        if first_authority[forbidden_true]:
            raise ContractError(f"provisional authority enabled {forbidden_true}")
    checks += 3
    allocation = load(root / "docs/design/v23/tooling/V21C07RequirementAllocationV1.json")
    if allocation["orderedAtomicClauseIDs"] != EXPECTED_ATOMIC_IDS:
        raise ContractError("allocation order differs")
    if [row["atomicClauseID"] for row in allocation["rows"]] != EXPECTED_ATOMIC_IDS:
        raise ContractError("allocation rows differ")
    if len({row["atomicClauseID"] for row in allocation["rows"]}) != 57:
        raise ContractError("allocation is missing or duplicated")
    if any(row["soleOwner"] not in CLOSURE_MEMBERS for row in allocation["rows"]):
        raise ContractError("allocation has an invalid owner")
    if allocation["c13InheritedClauseCount"] != 0:
        raise ContractError("C13 inherited forbidden C07 credit")
    if allocation["ownerCounts"] != {"V23-P00-C07": 18, "V23-P00-C09": 11, "V23-P00-C10": 12, "V23-P00-C11": 10, "V23-P00-C12": 6}:
        raise ContractError("allocation owner counts differ")
    if [row["ordinal"] for row in allocation["rows"]] != list(range(1, 58)):
        raise ContractError("allocation ordinals differ")
    allocation_schema = load(root / OUTPUT_PATHS[0])
    missing_row = copy.deepcopy(allocation)
    missing_row["rows"].pop()
    expect_contract_error(lambda: validate_schema(missing_row, allocation_schema))
    extra_key = copy.deepcopy(allocation)
    extra_key["unexpected"] = True
    expect_contract_error(lambda: validate_schema(extra_key, allocation_schema))
    tampered = copy.deepcopy(allocation)
    tampered["rows"][0]["obligation"] += " tampered"
    expect_contract_error(lambda: verify_digest(tampered))
    stale_authority = copy.deepcopy(allocation)
    stale_authority["authority"]["ledgerCASSequence"] = 18
    expect_contract_error(lambda: validate_schema(stale_authority, allocation_schema))
    polling = copy.deepcopy(allocation)
    polling["authority"]["phase10PollingDuringParallelExecution"] = True
    expect_contract_error(lambda: validate_schema(polling, allocation_schema))
    checks += 12
    closure = load(root / "docs/design/v23/tooling/V21C07ClosureSetV1.json")
    if closure["orderedMembers"] != CLOSURE_MEMBERS or [row["cardID"] for row in closure["members"]] != CLOSURE_MEMBERS:
        raise ContractError("closure member order differs")
    if sum(row["allocatedClauseCount"] for row in closure["members"]) != 57:
        raise ContractError("closure allocation count differs")
    if closure["sharedCandidateIdentity"] is not None or closure["acceptanceCredit"]:
        raise ContractError("provisional closure claimed acceptance")
    closure_schema = load(root / OUTPUT_PATHS[1])
    duplicate_member = copy.deepcopy(closure)
    duplicate_member["members"][1]["cardID"] = duplicate_member["members"][0]["cardID"]
    duplicate_member["members"][1]["candidateIdentity"] = "mismatched-candidate"
    expect_contract_error(lambda: validate_schema(duplicate_member, closure_schema))
    promoted = copy.deepcopy(closure)
    promoted["closureEligible"] = True
    expect_contract_error(lambda: validate_schema(promoted, closure_schema))
    checks += 5
    inventory = load(root / "docs/design/v23/tooling/ReleaseHookInventoryV1.json")
    if inventory["releaseAbsenceSatisfied"] or not inventory["findings"]:
        raise ContractError("Release inventory falsely claims absence")
    reserved = set(load(root / RESERVATION)["reservedPaths"])
    for finding in inventory["findings"]:
        expected_disposition = "DEFERRED_FROZEN_S10_RESERVED_PATH" if finding["path"] in reserved else "REQUIRES_C07_RELEASE_ISOLATION_REMEDIATION"
        if finding["disposition"] != expected_disposition:
            raise ContractError("hook finding reservation disposition differs")
    checks += 2
    absence = load(root / "docs/design/v23/tooling/ReleaseTestSupportAbsenceReceiptV1.json")
    if absence["inventoryDigest"] != inventory["artifactDigest"] or absence["disposition"] != "PROVISIONAL_NOT_SATISFIED":
        raise ContractError("absence receipt is not fail-closed")
    if absence["authority"]["frozenS10ReservationDigest"] != RESERVATION_DIGEST:
        raise ContractError("absence receipt reservation differs")
    absence_schema = load(root / OUTPUT_PATHS[3])
    fake_archive = copy.deepcopy(absence)
    fake_archive["archiveIdentity"] = "invented"
    expect_contract_error(lambda: validate_schema(fake_archive, absence_schema))
    fake_pass = copy.deepcopy(absence)
    fake_pass["disposition"] = "PASS"
    expect_contract_error(lambda: validate_schema(fake_pass, absence_schema))
    checks += 4
    support = "C:/sandbox/Library/Application Support"
    production = [f"{support}/FieldEvidenceData", f"{support}/FieldEvidenceRestore", f"{support}/FieldEvidenceOperations"]
    first = model_test_root(support, "run_123", production)
    second = model_test_root(support, "run_123", production)
    if first != second or not first.endswith("/TestRuns/run_123"):
        raise ContractError("test root is not deterministic")
    model_test_root(support, "A" * 64, production)
    expect_error(lambda: model_test_root(support, "../escape", production))
    expect_error(lambda: model_test_root(support, "nested/run", production))
    expect_error(lambda: model_test_root(support, "run", production, symlink_component=True))
    expect_error(lambda: model_test_root(support, "FieldEvidenceData", [f"{support}/TestRuns/FieldEvidenceData"]))
    checks += 6
    writer = load(root / "docs/design/v23/tooling/WriterBoundaryInterlockV1.json")
    if writer["observedForbiddenDeclarations"] or writer["futureCanonicalWriterOwner"] != "V23-P02-C01":
        raise ContractError("writer boundary interlock failed")
    if writer["futureSearchOwner"] != "V23-P03-C09" or writer["productMutationCount"] != 0:
        raise ContractError("writer/search ownership was claimed by C07")
    writer_schema = load(root / OUTPUT_PATHS[5])
    second_writer = copy.deepcopy(writer)
    second_writer["observedForbiddenDeclarations"] = ["FieldEvidenceApp/App/Competing.swift:1"]
    expect_contract_error(lambda: validate_schema(second_writer, writer_schema))
    checks += 3
    manifest = load(root / MANIFEST_PATH)
    expected_manifest = build_manifest(root)
    if manifest != expected_manifest:
        raise ContractError("tooling manifest differs")
    verify_digest(manifest)
    if manifest["fencedPathCount"] != len(FENCED_PATHS) or len(manifest["artifacts"]) != len(FENCED_PATHS) - 1:
        raise ContractError("tooling manifest path count differs")
    manifest_paths = [row["path"] for row in manifest["artifacts"]]
    if manifest_paths != [path for path in FENCED_PATHS if path != MANIFEST_PATH] or len(manifest_paths) != len(set(manifest_paths)):
        raise ContractError("tooling manifest fence differs or duplicates paths")
    reserved_paths = set(load(root / RESERVATION)["reservedPaths"])
    if set(FENCED_PATHS) & reserved_paths:
        raise ContractError("tooling manifest overlaps frozen S10 reservation")
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"manifest hash differs: {row['path']}")
    checks += 5
    completed = subprocess.run(
        [sys.executable, "-B", str(root / "Scripts/v23/generate_c07_contracts.py"), "--check", "--root", str(root)],
        check=True, capture_output=True, text=True,
    )
    if "PASS V23-P00-C07" not in completed.stdout:
        raise ContractError("generator check did not pass")
    checks += 1
    print(json.dumps({
        "result": "PASS", "cardID": CARD_ID, "checks": checks,
        "allocationRows": len(allocation["rows"]), "releaseHookFindings": len(inventory["findings"]),
        "releaseAbsenceSatisfied": False, "phase10PollingDuringParallelExecution": False,
        "acceptanceCredit": False, "releaseCredit": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

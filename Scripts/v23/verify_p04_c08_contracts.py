#!/usr/bin/env python3
"""Fail-closed verifier for the C08 tooling, source lanes, and fence."""
from __future__ import annotations

import argparse
import ast
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c08_contracts as contracts  # noqa: E402


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_bytes(), object_pairs_hook=contracts.strict)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + str(path))
    return value


def _assert_equal(value: dict[str, Any], field: str, expected: Any, label: str) -> None:
    if value.get(field) != expected:
        raise ValueError(label + " differs:" + field)


def _validate_schema(value: Any, schema: dict[str, Any], where: str = "$") -> None:
    if "const" in schema and value != schema["const"]:
        raise ValueError(where + ": schema const mismatch")
    expected_type = schema.get("type")
    if expected_type:
        types = {"object": dict, "array": list, "string": str, "integer": int, "boolean": bool, "null": type(None)}
        expected = types[expected_type]
        if not isinstance(value, expected) or (expected_type == "integer" and isinstance(value, bool)):
            raise ValueError(where + ": schema type mismatch")
    if isinstance(value, dict):
        required = set(schema.get("required", []))
        if required - set(value):
            raise ValueError(where + ": schema required field missing")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False and set(value) - set(properties):
            raise ValueError(where + ": schema extra field")
        for key, item in value.items():
            if key in properties:
                _validate_schema(item, properties[key], where + "." + key)
    elif isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            _validate_schema(item, schema["items"], where + "[" + str(index) + "]")


def _verify_common(document: dict[str, Any], label: str) -> None:
    _assert_equal(document, "cardID", contracts.CARD, label)
    _assert_equal(document, "status", "SEALED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED", label)
    _assert_equal(document, "finalHashesSealed", contracts.FINAL_HASHES_SEALED, label)
    _assert_equal(document, "provisional", not contracts.FINAL_HASHES_SEALED, label)
    _assert_equal(document, "statusFlags", contracts.FLAGS, label)
    for field in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "releaseCredit", "physicalEvidenceComplete"):
        _assert_equal(document, field, False, label)
    _assert_equal(document, "physicalLockedState", "REQUIRED_PENDING_OWNER", label)
    _assert_equal(document, "uiAdoptionSkipped", True, label)
    _assert_equal(document, "uiAcceptanceCredit", False, label)
    if contracts.FINAL_HASHES_SEALED:
        digest = document.get("artifactDigest")
        if not contracts.valid_sha(digest):
            raise ValueError(label + " sealed artifact digest missing")
        unsigned = {key: item for key, item in document.items() if key != "artifactDigest"}
        if digest != contracts.sha256_bytes(contracts.pretty(unsigned)):
            raise ValueError(label + " sealed artifact digest differs")
    elif document.get("artifactDigest") is not None:
        raise ValueError(label + " provisional artifact digest is not null")


def _verify_schema_document(document: dict[str, Any]) -> None:
    if set(document) != {"$schema", "$id", "title", "type", "additionalProperties", "properties", "required"}:
        raise ValueError("schema document is not strict")
    _assert_equal(document, "$id", "https://assetrounds.invalid/v23/import-bulk-engine.schema.json", "schema")
    _assert_equal(document, "title", "V23-P04-C08 import bulk engine", "schema")
    _assert_equal(document, "additionalProperties", False, "schema")
    properties = document.get("properties")
    if not isinstance(properties, dict):
        raise ValueError("schema properties missing")
    expected = {
        "schema": {"const": "IMPORT_BULK_ENGINE_V1"}, "schemaVersion": {"const": 1}, "cardID": {"const": contracts.CARD}, "ordinal": {"const": contracts.REGISTER_ORDINAL}, "selectors": {"const": list(contracts.EXPECTED_SELECTORS)}, "authorityContracts": {"const": list(contracts.AUTHORITY_CONTRACTS)}, "persistentKinds": {"const": list(contracts.PERSISTENT_KINDS)}, "rowDispositions": {"const": list(contracts.ROW_DISPOSITIONS)}, "executionStates": {"const": list(contracts.EXECUTION_STATES)}, "lifecycle": {"const": list(contracts.LIFECYCLE)}, "forbidden": {"const": list(contracts.FORBIDDEN)}, "semantics": {"const": contracts.semantics(tuple(contracts.EXPECTED_SELECTORS))}, "sourceReady": {"type": "boolean"}, "physicalLockedState": {"const": "REQUIRED_PENDING_OWNER"}, "uiAdoptionSkipped": {"const": True}, "uiAcceptanceCredit": {"const": False}, "statusFlags": {"const": dict(contracts.FLAGS)}, "finalHashesSealed": {"const": contracts.FINAL_HASHES_SEALED}, "provisional": {"const": not contracts.FINAL_HASHES_SEALED},
    }
    if properties != expected:
        raise ValueError("schema closed sets differ")
    if document.get("required") != list(expected):
        raise ValueError("schema required ordering differs")
    # Validate the schema's own structural type/closed-set shape with a
    # generated sample.  This catches accidental broadening of the schema.
    sample = {key: item["const"] for key, item in expected.items() if "const" in item}
    sample["sourceReady"] = False
    _validate_schema(sample, document)


def _verify_generated_documents(rendered: dict[str, bytes], source_ready: bool) -> None:
    for path, expected in rendered.items():
        target = ROOT / path
        if not target.is_file() or target.read_bytes() != expected:
            raise ValueError("generated artifact differs:" + path)
        document = _read_json(target)
        if path == contracts.SCHEMA_PATH:
            _verify_schema_document(document)
            continue
        _verify_common(document, path)
        if "authority" in document and document["authority"] != contracts.authority():
            raise ValueError("authority binding differs:" + path)
        if "semantics" in document and document["semantics"] != contracts.semantics(tuple(document["semantics"].get("selectors", contracts.EXPECTED_SELECTORS))):
            raise ValueError("semantic closed sets differ:" + path)
        if path == contracts.CONTRACT_PATH:
            for key, expected_value in (("authorityContracts", list(contracts.AUTHORITY_CONTRACTS)), ("persistentKinds", list(contracts.PERSISTENT_KINDS)), ("directPrerequisites", list(contracts.DIRECT_PREREQUISITES)), ("sourceProjection", contracts.source_projection(ROOT, contracts.EXPECTED_SELECTORS))):
                _assert_equal(document, key, expected_value, path)
        elif path == contracts.EVIDENCE_PATH:
            _assert_equal(document, "testSelectors", list(contracts.EXPECTED_SELECTORS), path)
            _assert_equal(document, "evidenceIDs", list(contracts.EVIDENCE_IDS), path)
            _assert_equal(document, "hostileVectors", list(contracts.HOSTILE_VECTORS), path)
        elif path == contracts.BRAND_PATH:
            _assert_equal(document, "nativeIPadSurface", False, path)
            _assert_equal(document, "adoptionSkipped", True, path)
            _assert_equal(document, "networkOrTelemetryFlow", False, path)
            _assert_equal(document, "providerOrNotificationFlow", False, path)
            _assert_equal(document, "recurrenceOrQRFlow", False, path)
        if document.get("sourceProjection", {}).get("sourceReady") != source_ready:
            raise ValueError("source readiness differs:" + path)
    manifest = _read_json(ROOT / contracts.MANIFEST_PATH)
    _verify_common(manifest, contracts.MANIFEST_PATH)
    for field, expected in (("existingPathCount", contracts.EXPECTED_EXISTING_PATH_COUNT), ("newPathCount", contracts.EXPECTED_NEW_PATH_COUNT), ("fencePathCount", contracts.EXPECTED_FENCE_PATH_COUNT), ("manifestInputCount", len(contracts.MANIFEST_INPUT_PATHS)), ("authorizedOverlapCount", contracts.AUTHORIZED_OVERLAP_COUNT), ("unauthorizedOverlapCount", contracts.UNAUTHORIZED_OVERLAP_COUNT), ("s10ReservationOverlapCount", contracts.S10_RESERVATION_OVERLAP_COUNT), ("priorFenceCount", contracts.PRIOR_FENCE_COUNT), ("priorOwnedPathCount", contracts.PRIOR_OWNED_PATH_COUNT), ("s10ReservedPathCount", contracts.S10_RESERVED_PATH_COUNT)):
        _assert_equal(manifest, field, expected, "manifest metric")
    for field, expected in (("pathFence", list(contracts.PATH_FENCE)), ("existingPaths", list(contracts.EXISTING_PATHS)), ("newPaths", list(contracts.NEW_PATHS)), ("toolingEditPaths", list(contracts.TOOLING_EDIT_PATHS)), ("authorityContracts", list(contracts.AUTHORITY_CONTRACTS)), ("persistentKinds", list(contracts.PERSISTENT_KINDS)), ("sourceReady", source_ready)):
        _assert_equal(manifest, field, expected, "manifest")
    expected_status = contracts.source_status(ROOT)
    _assert_equal(manifest, "sourceStatus", expected_status["status"], "manifest source")
    _assert_equal(manifest, "sourceReason", expected_status["reason"], "manifest source")
    expected_disposition = "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
    _assert_equal(manifest, "hashDisposition", expected_disposition, "manifest hash")
    rows = manifest.get("files")
    if not isinstance(rows, list) or tuple(row.get("path") for row in rows if isinstance(row, dict)) != contracts.MANIFEST_INPUT_PATHS:
        raise ValueError("manifest file rows/order differs")
    if contracts.FINAL_HASHES_SEALED:
        if not contracts.valid_sha(manifest.get("artifactSetDigest")):
            raise ValueError("sealed artifact set digest missing")
        if manifest["artifactSetDigest"] != contracts.sha256_bytes(contracts.canonical(rows)):
            raise ValueError("sealed artifact set digest differs")
        for path in contracts.TOOLING_EDIT_PATHS:
            if path == contracts.MANIFEST_PATH:
                continue
            row = next(item for item in rows if item.get("path") == path)
            if not contracts.valid_sha(row.get("sha256")) or row.get("status") != "SEALED_TOOLING":
                raise ValueError("sealed owned-file hash missing:" + path)
    elif manifest.get("artifactSetDigest") is not None:
        raise ValueError("provisional artifact set was sealed")


def _source_hashes() -> dict[str, str | None]:
    return {path: contracts.sha256_bytes(contracts.canonical_file_bytes(ROOT / path)) if (ROOT / path).is_file() else None for path in contracts.IMPLEMENTATION_PATHS}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all source lanes and final seal")
    parser.add_argument("--json", action="store_true", help="emit JSON evidence")
    args = parser.parse_args()
    failures: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
    except Exception as error:
        failures.append("scaffold:" + str(error))
    for path in contracts.SCRIPT_PATHS:
        try:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        except Exception as error:
            failures.append("AST:" + path + ":" + str(error))
    source_before = _source_hashes()
    source = contracts.source_status(ROOT)
    if args.complete:
        if not source["sourceReady"]:
            failures.append("source:C08 source lanes missing:" + ",".join(source["missingPaths"]))
        if not contracts.FINAL_HASHES_SEALED:
            failures.append("seal:finalHashesSealed=false until source stability and owner authorization")
    if source["hydrated"]:
        try:
            # V9_72 may construct SwiftData only as an in-memory test harness;
            # the lifecycle adapter exercised by that harness must be the
            # production ImportBulkLifecycleAdapterV1 API.
            contracts.assert_v9_72_test_harness_boundary(ROOT)
        except Exception as error:
            failures.append("harness:" + str(error))
        try:
            contracts.assert_source_contracts(ROOT)
        except Exception as error:
            failures.append("source:" + str(error))
    rendered: dict[str, bytes] = {}
    try:
        rendered = contracts.outputs(ROOT)
        _verify_generated_documents(rendered, source["sourceReady"])
    except Exception as error:
        failures.append("outputs:" + str(error))
    source_after = _source_hashes()
    if source_before != source_after:
        failures.append("source:bytes changed during verification")
    cache_dirs = [path for path in (ROOT / "Scripts" / "v23").rglob("__pycache__") if path.is_dir()]
    if cache_dirs:
        failures.append("cache:__pycache__ present")
    artifact_hashes = {path: contracts.sha256_bytes(data) for path, data in rendered.items()}
    report = {"cardID": contracts.CARD, "complete": args.complete, "result": "FAIL_STATIC" if failures else ("PASS_STATIC_SEALED" if contracts.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"), "failures": failures, "sourceReady": source["sourceReady"], "sourceStatus": source["status"], "sourceReason": source["reason"], "sourceMissing": source["missingPaths"], "selectors": source["selectors"] or list(contracts.EXPECTED_SELECTORS), "expectedSelectors": list(contracts.EXPECTED_SELECTORS), "sourceHashes": source_after, "artifactHashes": artifact_hashes, "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS), "fencePathCount": len(contracts.PATH_FENCE), "manifestInputCount": len(contracts.MANIFEST_INPUT_PATHS), "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": contracts.S10_RESERVATION_OVERLAP_COUNT, "finalHashesSealed": contracts.FINAL_HASHES_SEALED, "flagsAllFalse": all(value is False for value in contracts.FLAGS.values()), "generatedArtifactCount": len(rendered), "coldLaunchRebuild": "DROP_AND_REBUILD_FROM_CANONICAL_PROFILE_SESSION_RECEIPT_INPUTS", "zeroWritePreview": True, "uiAdoptionSkipped": True, "accessibilityAndLocalizationRequired": True}
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) if args.json else report["result"])
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

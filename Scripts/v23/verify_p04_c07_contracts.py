#!/usr/bin/env python3
"""Fail-closed verifier for the C07 tooling and hydrated source lanes."""
from __future__ import annotations

import argparse
import ast
import json
import os
import sys
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c07_contracts as contracts  # noqa: E402


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_bytes(), object_pairs_hook=contracts.strict)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + str(path))
    return value


def _assert_equal(document: dict[str, Any], field: str, expected: Any, label: str) -> None:
    if document.get(field) != expected:
        raise ValueError(label + " differs:" + field)


def _verify_generated_documents(rendered: dict[str, bytes], source_ready: bool) -> None:
    expected_status = "SEALED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED"
    for path, expected in rendered.items():
        target = ROOT / path
        if not target.is_file():
            raise ValueError("generated artifact absent:" + path)
        if target.read_bytes() != expected:
            raise ValueError("generated artifact differs:" + path)
        document = _read_json(target)
        if path == contracts.SCHEMA_PATH:
            _assert_equal(document, "$id", "https://assetrounds.invalid/v23/round-session-field-flow.schema.json", "schema identity")
            _assert_equal(document, "title", "V23-P04-C07 RoundSession field flow", "schema title")
            _assert_equal(document, "additionalProperties", False, "schema closed-set policy")
            properties = document.get("properties")
            if not isinstance(properties, dict):
                raise ValueError("schema properties missing")
            _assert_equal(properties, "selectors", {"const": contracts.source_status(ROOT)["selectors"]}, "schema")
            _assert_equal(properties, "counts", {"const": list(contracts.COUNTS)}, "schema")
            _assert_equal(properties, "dispositions", {"const": list(contracts.DISPOSITIONS)}, "schema")
            _assert_equal(properties, "sessionStates", {"const": list(contracts.SESSION_STATES)}, "schema")
            _assert_equal(properties, "transitions", {"const": list(contracts.TRANSITIONS)}, "schema")
            _assert_equal(properties, "lifecycle", {"const": list(contracts.LIFECYCLE)}, "schema")
            _assert_equal(properties, "forbidden", {"const": list(contracts.FORBIDDEN)}, "schema")
            _assert_equal(properties, "physicalLockedState", {"const": "REQUIRED_PENDING_OWNER"}, "schema")
            _assert_equal(properties, "uiAdoptionSkipped", {"const": True}, "schema")
            _assert_equal(properties, "uiAcceptanceCredit", {"const": False}, "schema")
            _assert_equal(properties, "finalHashesSealed", {"const": contracts.FINAL_HASHES_SEALED}, "schema")
            _assert_equal(properties, "provisional", {"const": not contracts.FINAL_HASHES_SEALED}, "schema")
            continue

        _assert_equal(document, "cardID", contracts.CARD, "generated card identity")
        _assert_equal(document, "status", expected_status, "generated status")
        _assert_equal(document, "finalHashesSealed", contracts.FINAL_HASHES_SEALED, "generated seal flag")
        _assert_equal(document, "provisional", not contracts.FINAL_HASHES_SEALED, "generated provisional flag")
        _assert_equal(document, "statusFlags", contracts.FLAGS, "generated status flags")
        _assert_equal(document, "physicalLockedState", "REQUIRED_PENDING_OWNER", "generated physical lock")
        _assert_equal(document, "uiAdoptionSkipped", True, "generated UI skip disposition")
        _assert_equal(document, "uiAcceptanceCredit", False, "generated UI acceptance credit")
        for field in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "releaseCredit", "physicalEvidenceComplete"):
            _assert_equal(document, field, False, "generated activation flag")
        if contracts.FINAL_HASHES_SEALED:
            artifact_digest = document.get("artifactDigest")
            if not contracts.valid_sha(artifact_digest):
                raise ValueError("sealed artifact digest missing:" + path)
            unsigned = {key: value for key, value in document.items() if key != "artifactDigest"}
            if artifact_digest != contracts.sha256_bytes(contracts.pretty(unsigned)):
                raise ValueError("sealed artifact digest differs:" + path)
        if "semantics" in document:
            semantics = document.get("semantics")
            if not isinstance(semantics, dict) or semantics != contracts.semantics(tuple(semantics.get("selectors", ()))):
                raise ValueError("generated semantic closed sets differ:" + path)

    manifest = _read_json(ROOT / contracts.MANIFEST_PATH)
    for field, expected in (
        ("existingPathCount", contracts.EXPECTED_EXISTING_PATH_COUNT),
        ("newPathCount", contracts.EXPECTED_NEW_PATH_COUNT),
        ("fencePathCount", contracts.EXPECTED_FENCE_PATH_COUNT),
        ("manifestInputCount", len(contracts.MANIFEST_INPUT_PATHS)),
        ("authorizedOverlapCount", contracts.AUTHORIZED_OVERLAP_COUNT),
        ("unauthorizedOverlapCount", contracts.UNAUTHORIZED_OVERLAP_COUNT),
        ("s10ReservationOverlapCount", contracts.S10_RESERVATION_OVERLAP_COUNT),
        ("priorFenceCount", contracts.PRIOR_FENCE_COUNT),
        ("priorOwnedPathCount", contracts.PRIOR_OWNED_PATH_COUNT),
        ("s10ReservedPathCount", contracts.S10_RESERVED_PATH_COUNT),
    ):
        _assert_equal(manifest, field, expected, "manifest metric")
    _assert_equal(manifest, "pathFence", list(contracts.PATH_FENCE), "manifest fence")
    _assert_equal(manifest, "newPaths", list(contracts.NEW_PATHS), "manifest new paths")
    _assert_equal(manifest, "toolingEditPaths", list(contracts.TOOLING_EDIT_PATHS), "manifest tooling paths")
    _assert_equal(manifest, "sourceReady", source_ready, "manifest source readiness")
    expected_source = contracts.source_status(ROOT)
    _assert_equal(manifest, "sourceStatus", expected_source["status"], "manifest source status")
    _assert_equal(manifest, "sourceReason", expected_source["reason"], "manifest source reason")
    expected_hash_disposition = "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
    _assert_equal(manifest, "hashDisposition", expected_hash_disposition, "manifest hash disposition")
    artifact_set_digest = manifest.get("artifactSetDigest")
    if contracts.FINAL_HASHES_SEALED:
        if not contracts.valid_sha(artifact_set_digest):
            raise ValueError("sealed artifact set digest differs")
        rows = manifest.get("files")
        if not isinstance(rows, list) or len(rows) != len(contracts.MANIFEST_INPUT_PATHS):
            raise ValueError("sealed manifest file rows differ")
        row_by_path = {row.get("path"): row for row in rows if isinstance(row, dict)}
        if tuple(row_by_path) != contracts.MANIFEST_INPUT_PATHS:
            raise ValueError("sealed manifest file ordering differs")
        for path in contracts.TOOLING_EDIT_PATHS:
            if path == contracts.MANIFEST_PATH:
                continue
            row = row_by_path.get(path)
            if not isinstance(row, dict) or not contracts.valid_sha(row.get("sha256")) or row.get("status") != "SEALED_TOOLING":
                raise ValueError("sealed owned-file hash missing:" + path)
        if artifact_set_digest != contracts.sha256_bytes(contracts.canonical(rows)):
            raise ValueError("sealed artifact set digest does not match rows")
        manifest_digest = manifest.get("artifactDigest")
        if not contracts.valid_sha(manifest_digest):
            raise ValueError("sealed manifest artifact digest missing")
        unsigned_manifest = {key: value for key, value in manifest.items() if key != "artifactDigest"}
        if manifest_digest != contracts.sha256_bytes(contracts.pretty(unsigned_manifest)):
            raise ValueError("sealed manifest artifact digest differs")
    elif artifact_set_digest is not None:
        raise ValueError("provisional artifact set was sealed")


def _source_hashes() -> dict[str, str | None]:
    values: dict[str, str | None] = {}
    for path in contracts.IMPLEMENTATION_PATHS:
        target = ROOT / path
        values[path] = contracts.sha256_bytes(contracts.canonical_file_bytes(target)) if target.is_file() else None
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require hydrated source and final byte sealing")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable report")
    args = parser.parse_args()
    failures: list[str] = []

    try:
        contracts.assert_scaffold(ROOT)
    except Exception as error:  # pragma: no cover - CLI failure reporting
        failures.append("scaffold:" + str(error))

    for path in contracts.SCRIPT_PATHS:
        try:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        except Exception as error:  # pragma: no cover - CLI failure reporting
            failures.append("AST:" + path + ":" + str(error))

    source = contracts.source_status(ROOT)
    if args.complete:
        if not source["sourceReady"]:
            failures.append("source:C07 source lanes missing:" + ",".join(source["missingPaths"]))
        if not contracts.FINAL_HASHES_SEALED:
            failures.append("seal:finalHashesSealed=false until owner authorization")
    if source["hydrated"]:
        try:
            contracts.assert_source_contracts(ROOT)
        except Exception as error:  # pragma: no cover - CLI failure reporting
            failures.append("source:" + str(error))

    rendered: dict[str, bytes] = {}
    try:
        rendered = contracts.outputs(ROOT)
        _verify_generated_documents(rendered, source["sourceReady"])
    except Exception as error:  # pragma: no cover - CLI failure reporting
        failures.append("outputs:" + str(error))

    artifact_hashes = {path: contracts.sha256_bytes(data) for path, data in rendered.items()}
    report = {
        "cardID": contracts.CARD,
        "complete": args.complete,
        "result": "FAIL_STATIC" if failures else ("PASS_STATIC_SEALED" if contracts.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"),
        "failures": failures,
        "sourceReady": source["sourceReady"],
        "sourceStatus": source["status"],
        "sourceReason": source["reason"],
        "sourceMissing": source["missingPaths"],
        "selectors": source["selectors"],
        "sourceHashes": _source_hashes(),
        "artifactHashes": artifact_hashes,
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "fencePathCount": len(contracts.PATH_FENCE),
        "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": contracts.S10_RESERVATION_OVERLAP_COUNT,
        "finalHashesSealed": contracts.FINAL_HASHES_SEALED,
        "flagsAllFalse": all(value is False for value in contracts.FLAGS.values()),
        "generatedArtifactCount": len(rendered),
        "coldLaunchRebuild": "DETERMINISTIC_REBUILD_FROM_CANONICAL_SESSION_AND_FIELD_INPUTS",
        "uiAdoptionSkipped": True,
        "accessibilityAndLocalizationRequired": True,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) if args.json else report["result"])
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

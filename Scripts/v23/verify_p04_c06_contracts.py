#!/usr/bin/env python3
"""Fail-closed static verifier for the C06 tooling and live source lanes."""
from __future__ import annotations

import argparse
import ast
import json
import os
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c06_contracts as contracts  # noqa: E402


def _read_json(path: Path) -> dict[str, object]:
    value = json.loads(path.read_bytes(), object_pairs_hook=contracts.strict)
    if not isinstance(value, dict):
        raise ValueError("JSON object required")
    return value


def _verify_generated_documents(rendered: dict[str, bytes]) -> None:
    expected_status = "SEALED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED"
    for path, expected in rendered.items():
        target = ROOT / path
        if not target.is_file():
            raise ValueError("generated artifact absent:" + path)
        if target.read_bytes() != expected:
            raise ValueError("generated artifact differs:" + path)
        document = _read_json(target)
        if path == contracts.SCHEMA_PATH:
            if document.get("$id") != "https://assetrounds.invalid/v23/offline-readiness-manifest.schema.json":
                raise ValueError("schema identity differs")
        elif document.get("cardID") != contracts.CARD:
            raise ValueError("generated card identity differs:" + path)
        if path != contracts.SCHEMA_PATH:
            if document.get("status") != expected_status:
                raise ValueError("generated status differs:" + path)
            if document.get("finalHashesSealed") is not contracts.FINAL_HASHES_SEALED:
                raise ValueError("generated seal flag differs:" + path)
            if document.get("provisional") is not (not contracts.FINAL_HASHES_SEALED):
                raise ValueError("generated provisional flag differs:" + path)
            if document.get("statusFlags") != contracts.FLAGS:
                raise ValueError("generated status flags differ:" + path)
            if document.get("uiAdoptionSkipped") is not True:
                raise ValueError("generated UI skip disposition differs:" + path)

    manifest = _read_json(ROOT / contracts.MANIFEST_PATH)
    if manifest.get("existingPathCount") != contracts.EXPECTED_EXISTING_PATH_COUNT:
        raise ValueError("manifest existing-path count differs")
    if manifest.get("newPathCount") != contracts.EXPECTED_NEW_PATH_COUNT:
        raise ValueError("manifest new-path count differs")
    if manifest.get("fencePathCount") != contracts.EXPECTED_FENCE_PATH_COUNT:
        raise ValueError("manifest fence-path count differs")
    if manifest.get("authorizedOverlapCount") != contracts.AUTHORIZED_OVERLAP_COUNT:
        raise ValueError("manifest authorized overlap differs")
    if manifest.get("unauthorizedOverlapCount") != contracts.UNAUTHORIZED_OVERLAP_COUNT:
        raise ValueError("manifest unauthorized overlap differs")
    if manifest.get("s10ReservationOverlapCount") != contracts.S10_RESERVATION_OVERLAP_COUNT:
        raise ValueError("manifest S10 overlap differs")
    if manifest.get("sourceReady") is not True:
        raise ValueError("manifest source is not ready")
    if manifest.get("sourceStatus") != "SOURCE_READY":
        raise ValueError("manifest source status differs")
    if manifest.get("sourceReason") != "ALL_IMPLEMENTATION_SOURCE_LANES_PRESENT":
        raise ValueError("manifest source reason differs")
    expected_hash_disposition = (
        "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
        if contracts.FINAL_HASHES_SEALED
        else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
    )
    if manifest.get("hashDisposition") != expected_hash_disposition:
        raise ValueError("manifest hash disposition differs")
    artifact_set_digest = manifest.get("artifactSetDigest")
    if contracts.FINAL_HASHES_SEALED:
        if not contracts.valid_sha(artifact_set_digest):
            raise ValueError("sealed artifact set digest differs")
    elif artifact_set_digest is not None:
        raise ValueError("provisional artifact set was sealed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all live source contract assertions")
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
    if args.complete or source["hydrated"]:
        try:
            contracts.assert_source_contracts(ROOT)
        except Exception as error:  # pragma: no cover - CLI failure reporting
            failures.append("source:" + str(error))

    rendered: dict[str, bytes] = {}
    try:
        rendered = contracts.outputs(ROOT)
        _verify_generated_documents(rendered)
    except Exception as error:  # pragma: no cover - CLI failure reporting
        failures.append("outputs:" + str(error))

    report = {
        "cardID": contracts.CARD,
        "complete": args.complete,
        "result": "FAIL_STATIC" if failures else (
            "PASS_STATIC_SEALED" if contracts.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"
        ),
        "failures": failures,
        "sourceReady": source["sourceReady"],
        "sourceStatus": source["status"],
        "sourceReason": source["reason"],
        "sourceMissing": source["missingPaths"],
        "selectors": source["selectors"],
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "fencePathCount": len(contracts.PATH_FENCE),
        "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": contracts.S10_RESERVATION_OVERLAP_COUNT,
        "finalHashesSealed": contracts.FINAL_HASHES_SEALED,
        "flagsAllFalse": all(value is False for value in contracts.FLAGS.values()),
        "generatedArtifactCount": len(rendered),
        "coldLaunchRebuild": "DETERMINISTIC_INVALIDATION_AND_REBUILD",
        "uiAdoptionSkipped": True,
        "accessibilityAndLocalizationRequired": True,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) if args.json else report["result"])
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run the sealed portable validator over the P03-C06 schema/corpus."""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import portable_contract_validator_v1 as portable


FIXTURE = "FieldEvidenceAppTests/Fixtures/V21/Contracts/V21P03C06SnapshotProjectionCorpusV1.json"
C06_MODULE = "Scripts/v23/p03_c06_contracts.py"


def _load_module(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise portable.PortableContractError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise portable.PortableContractError(message)


def _result_row(label: str, schema_path: str, expected: bool, result: dict[str, Any]) -> dict[str, Any]:
    errors = result["errors"]
    return {
        "label": label,
        "schemaPath": schema_path,
        "expectedValid": expected,
        "valid": result["valid"],
        "expectationMatched": result["valid"] is expected,
        "resultClasses": sorted({row["resultClass"] for row in errors}),
        "instancePaths": sorted({row["instancePath"] for row in errors}),
        "schemaPaths": sorted({row["schemaPath"] for row in errors}),
    }


def _run_once(root: Path, registry: dict[str, Any]) -> dict[str, Any]:
    c06 = _load_module(root / C06_MODULE, "assetrounds_p03_c06_contracts")
    fixture = portable.strict_load(root / FIXTURE)
    _require(isinstance(fixture, dict), "C06 fixture is not an object")
    _require(fixture.get("schema") == "V21P03C06SnapshotProjectionCorpusV1", "C06 fixture identity differs")

    schemas = {relative: portable.strict_load(root / relative) for relative in c06.SCHEMA_PATHS}
    positive_instances = c06.sample_instances(fixture)
    positive_instances[c06.SCHEMA_PATHS[4]] = portable.strict_load(root / c06.CONTRACT_PATHS[2])
    positive_instances[c06.SCHEMA_PATHS[5]] = portable.strict_load(root / c06.CONTRACT_PATHS[4])
    _require(set(positive_instances) == set(c06.SCHEMA_PATHS), "C06 positive/schema inventory differs")

    meta_results: list[dict[str, Any]] = []
    positive_results: list[dict[str, Any]] = []
    for relative in c06.SCHEMA_PATHS:
        schema = schemas[relative]
        meta = portable.validate_schema_against_official_meta(schema, registry, (root / relative).resolve().as_uri())
        meta_results.append({
            "schemaPath": relative,
            "valid": meta["valid"],
            "resultClasses": sorted({row["resultClass"] for row in meta["errors"]}),
            "instancePaths": sorted({row["instancePath"] for row in meta["errors"]}),
            "schemaPaths": sorted({row["schemaPath"] for row in meta["errors"]}),
        })
        result = portable.validate_instance(positive_instances[relative], schema, registry, (root / relative).resolve().as_uri())
        positive_results.append(_result_row(f"POSITIVE_{Path(relative).stem.upper().replace('-', '_')}", relative, True, result))

    hostile = c06.negative_sample_instances(fixture)
    _require([row["label"] for row in hostile] == fixture["schemaNegativeCases"], "C06 hostile label inventory differs")
    hostile_results: list[dict[str, Any]] = []
    for row in hostile:
        relative = row["schemaPath"]
        result = portable.validate_instance(row["instance"], schemas[relative], registry, (root / relative).resolve().as_uri())
        hostile_results.append(_result_row(row["label"], relative, False, result))

    return {
        "metaSchemaResults": meta_results,
        "positiveResults": positive_results,
        "hostileResults": hostile_results,
        "metaSchemaValid": all(row["valid"] for row in meta_results),
        "positiveCaseCount": len(positive_results),
        "hostileCaseCount": len(hostile_results),
        "allExpectationsMatched": (
            all(row["valid"] for row in meta_results)
            and all(row["expectationMatched"] for row in positive_results)
            and all(row["expectationMatched"] for row in hostile_results)
        ),
    }


def run(root: Path) -> dict[str, Any]:
    checker = _load_module(root / "Scripts/v21-contracts/check-portable-contract-lock.py", "assetrounds_portable_lock_checker")
    lock_check = checker.verify_lock(root)
    lock = portable.load_lock(root)
    registry = portable.load_registry(root, lock)
    first = _run_once(root, registry)
    second = _run_once(root, registry)
    deterministic = portable.canonical_json(first) == portable.canonical_json(second)
    return {
        "schema": "PortableContractValidationRunV1",
        "schemaVersion": 1,
        "toolID": lock["tool"]["toolID"],
        "draft": lock["officialMetaSchema"]["draft"],
        "lockSHA256": lock_check["lockSHA256"],
        "networkFetchCount": 0,
        "deterministicReplayMatched": deterministic,
        **first,
        "valid": first["allExpectationsMatched"] and deterministic,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)
    try:
        result = run(portable.repository_root(Path(__file__)))
    except (portable.PortableContractError, OSError, ValueError) as error:
        result = {"schema": "PortableContractValidationRunV1", "schemaVersion": 1, "valid": False, "toolError": str(error)}
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())

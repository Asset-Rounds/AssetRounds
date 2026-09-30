#!/usr/bin/env python3
"""Verify V23-P00-C09 test-plan, scenario, robot, viewport, and source-lock contracts."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

from c07_contracts import digest, sha256_bytes
from c09_contracts import (
    ARTIFACT_PATHS,
    CARD_ID,
    FENCED_PATHS,
    MANIFEST_PATH,
    PLAN_DEFINITIONS,
    PLAN_PATHS,
    SCHEMA_PATHS,
    ContractError,
    build_manifest,
    build_outputs,
    pretty_bytes,
)
from verify_c07_contracts import validate_schema, verify_digest


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def expect_failure(callable_value) -> None:
    try:
        callable_value()
    except (ContractError, ValueError):
        return
    raise ContractError("hostile C09 case did not fail")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    expected = build_outputs(root)
    checks = 0
    for relative, value in expected.items():
        if not (root / relative).is_file() or (root / relative).read_bytes() != pretty_bytes(value):
            raise ContractError(f"generated C09 output differs: {relative}")
        checks += 1
    for index, schema_path in enumerate(SCHEMA_PATHS):
        schema = load(root / schema_path)
        artifact = load(root / ARTIFACT_PATHS[index])
        validate_schema(artifact, schema)
        verify_digest(artifact)
        checks += 2
    plan_release = load(root / ARTIFACT_PATHS[0])
    if [row["planID"] for row in plan_release["plans"]] != [row["id"] for row in PLAN_DEFINITIONS]:
        raise ContractError("test plan order differs")
    if sum(row["gating"] for row in plan_release["plans"]) != 4 or sum(row["diagnosticOnly"] for row in plan_release["plans"]) != 1:
        raise ContractError("gating/diagnostic topology differs")
    if next(row for row in plan_release["plans"] if row["diagnosticOnly"])["gating"]:
        raise ContractError("diagnostic plan can gate")
    checks += 3
    configuration_ids = []
    selected_class_count = 0
    for path in PLAN_PATHS:
        value = load(root / path)
        if set(value) != {"configurations", "defaultOptions", "testTargets", "version"} or value["version"] != 1:
            raise ContractError(f"invalid xctestplan shape: {path}")
        if len(value["configurations"]) != 1 or not value["testTargets"]:
            raise ContractError(f"invalid xctestplan topology: {path}")
        configuration_ids.append(value["configurations"][0]["id"])
        selected_class_count += sum(len(row.get("selectedTests", [])) for row in value["testTargets"])
    if len(set(configuration_ids)) != 5:
        raise ContractError("test plan configuration IDs duplicate")
    if selected_class_count != 14:
        raise ContractError("selected test class topology differs")
    checks += 6
    scenario = load(root / ARTIFACT_PATHS[1])
    scenario_schema = load(root / SCHEMA_PATHS[1])
    if len(pretty_bytes(scenario)) > 65536 or scenario["fixtureDigests"] or scenario["sourceClassification"] != "SYNTHETIC_ONLY":
        raise ContractError("scenario is unbounded or non-synthetic")
    unknown = copy.deepcopy(scenario); unknown["unknown"] = True
    expect_failure(lambda: validate_schema(unknown, scenario_schema))
    traversal = copy.deepcopy(scenario); traversal["opaqueRunID"] = "../escape"
    expect_failure(lambda: validate_schema(traversal, scenario_schema))
    corrupt = copy.deepcopy(scenario); corrupt["scenarioID"] += ".changed"
    expect_failure(lambda: verify_digest(corrupt))
    checks += 4
    robots = load(root / ARTIFACT_PATHS[2])
    if robots["legacyUITestClassCount"] != 32 or len(robots["robots"]) != 32:
        raise ContractError("robot registry does not cover 32 UI test classes")
    if len({row["robotID"] for row in robots["robots"]}) != 32 or len({row["legacyTestClass"] for row in robots["robots"]}) != 32:
        raise ContractError("robot registry duplicates identity")
    checks += 2
    viewport = load(root / ARTIFACT_PATHS[3])
    if viewport["preconditionOrder"] != ["SEMANTIC_ANCHOR", "VIEWPORT", "SAFE_AREA", "VISIBILITY", "REACHABILITY"]:
        raise ContractError("viewport precondition order differs")
    checks += 1
    source_lock = load(root / ARTIFACT_PATHS[4])
    if source_lock["findingCount"] != len(source_lock["findings"]) or source_lock["findingCount"] < 1 or source_lock["eliminationSatisfied"]:
        raise ContractError("source-lock receipt is not fail-closed")
    if not any(row["path"].endswith("S9_1ReleasePreflightTests.swift") for row in source_lock["findings"]):
        raise ContractError("source-lock scanner missed S9.1 source locks")
    observed_lock_kinds = {row["kind"] for row in source_lock["findings"]}
    if not {"DIRECT_SOURCE_TEXT_LOCK", "SOURCE_VALIDATOR_TEXT_LOCK"} <= observed_lock_kinds:
        raise ContractError("source-lock scanner missed direct or validator-mediated source assertions")
    checks += 2
    acceptance = load(root / ARTIFACT_PATHS[5])
    enrollment = load(root / ARTIFACT_PATHS[6])
    scenario_digest = load(root / ARTIFACT_PATHS[7])
    if acceptance["disposition"] != "PROVISIONAL_NOT_ACCEPTABLE" or acceptance["nativePlanDiscovery"] != "NOT_RUN_HOSTED_DISPATCH_DISABLED":
        raise ContractError("C09 acceptance receipt is not provisional")
    if enrollment["enrolledPlanCount"] != 0 or not enrollment["schemeReservedByS10"]:
        raise ContractError("C09 falsely claims plan enrollment")
    if scenario_digest["scenarioArtifactDigest"] != scenario["artifactDigest"] or scenario_digest["arbitraryPathAllowed"]:
        raise ContractError("scenario digest contract differs")
    checks += 3
    authorities = [load(root / path)["authority"] for path in ARTIFACT_PATHS]
    if any(value != authorities[0] for value in authorities[1:]):
        raise ContractError("C09 cross-artifact authority differs")
    if any(authorities[0][key] for key in ("phase10PollingDuringParallelExecution", "acceptanceEnabled", "hostedDispatchEnabled", "adoptionEnabled", "releaseCredit")):
        raise ContractError("C09 provisional authority enabled forbidden capability")
    checks += 2
    manifest = load(root / MANIFEST_PATH)
    if manifest != build_manifest(root):
        raise ContractError("C09 manifest differs")
    verify_digest(manifest)
    paths = [row["path"] for row in manifest["artifacts"]]
    if paths != [path for path in FENCED_PATHS if path != MANIFEST_PATH] or len(paths) != len(set(paths)):
        raise ContractError("C09 manifest path fence differs")
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"C09 manifest hash differs: {row['path']}")
    checks += 3
    completed = subprocess.run(
        [sys.executable, "-B", str(root / "Scripts/v23/generate_c09_contracts.py"), "--check", "--root", str(root)],
        check=True, capture_output=True, text=True,
    )
    if "PASS V23-P00-C09" not in completed.stdout:
        raise ContractError("C09 deterministic generator check failed")
    checks += 1
    print(json.dumps({
        "result": "PASS", "cardID": CARD_ID, "checks": checks, "planCount": 5,
        "uiTestClassCount": robots["legacyUITestClassCount"], "sourceLockFindingCount": source_lock["findingCount"],
        "planEnrollmentCount": 0, "nativeExecutionRan": False,
        "phase10PollingDuringParallelExecution": False, "acceptanceCredit": False, "releaseCredit": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

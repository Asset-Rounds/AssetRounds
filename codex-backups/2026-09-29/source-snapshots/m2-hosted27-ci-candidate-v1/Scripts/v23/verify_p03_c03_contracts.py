#!/usr/bin/env python3
"""Hostile static verifier for Card 34's closed typed-response contract."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

import p03_c03_contracts as contracts


class VerificationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout.strip()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def changed_paths(root: Path) -> set[str]:
    tracked = set(filter(None, git(root, "diff", "--name-only", contracts.APP_BASE_HEAD).splitlines()))
    untracked = set(filter(None, git(root, "ls-files", "--others", "--exclude-standard").splitlines()))
    return {value.replace("\\", "/") for value in tracked | untracked}


def strict_schema(value: object, path: str) -> None:
    require(isinstance(value, dict), f"{path}: schema is not an object")
    require(value.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{path}: dialect differs")
    if "anyOf" in value:
        require(isinstance(value["anyOf"], list) and value["anyOf"], f"{path}: closed variants missing")
        for index, variant in enumerate(value["anyOf"]):
            require(variant.get("type") == "object", f"{path}: variant {index} type differs")
            require(variant.get("additionalProperties") is False, f"{path}: variant {index} is open")
            require(isinstance(variant.get("required"), list) and variant["required"], f"{path}: variant {index} required set missing")
            require(isinstance(variant.get("properties"), dict), f"{path}: variant {index} properties missing")
    else:
        require(value.get("type") == "object", f"{path}: root type differs")
        require(value.get("additionalProperties") is False, f"{path}: root is open")
        require(isinstance(value.get("required"), list) and value["required"], f"{path}: required set missing")
        require(isinstance(value.get("properties"), dict), f"{path}: properties missing")


def verify(root: Path) -> dict[str, object]:
    require(git(root, "rev-parse", "HEAD") == contracts.APP_BASE_HEAD, "application HEAD differs from hydrated base")
    require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE, "application base tree differs")
    require(len(contracts.PATH_FENCE) == 24 and len(set(contracts.PATH_FENCE)) == 24, "path fence is not exact")
    require(contracts.PATH_FENCE[:4] == contracts.EXISTING_PATHS, "existing fence order differs")
    require(len(contracts.NEW_PATHS) == 20, "new path count differs")
    for relative in contracts.PATH_FENCE:
        require((root / relative).is_file(), f"missing fenced path: {relative}")

    observed = changed_paths(root)
    require(observed == set(contracts.PATH_FENCE), f"changed path set differs: {sorted(observed ^ set(contracts.PATH_FENCE))}")
    base_existing = {
        path for path in contracts.PATH_FENCE
        if subprocess.run(
            ["git", "-C", str(root), "cat-file", "-e", f"{contracts.APP_BASE_HEAD}:{path}"],
            capture_output=True,
        ).returncode == 0
    }
    require(base_existing == set(contracts.EXISTING_PATHS), "base existing/new partition differs")
    reservation = load_json(root / "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json")
    require(reservation["contentDigest"] == contracts.S10_RESERVATION_DIGEST, "S10 reservation digest differs")
    require(reservation["reservedPathCount"] == 86 and len(reservation["reservedPaths"]) == 86, "S10 reservation count differs")
    require(not set(contracts.PATH_FENCE) & set(reservation["reservedPaths"]), "S10 reservation overlap")

    outputs = contracts.all_outputs(root)
    require(set(outputs) == set(contracts.GENERATED_PATHS), "generated output set differs")
    for relative, expected in outputs.items():
        require((root / relative).read_bytes() == expected, f"stale generated artifact: {relative}")

    schemas = {}
    schema_paths = [
        contracts.RESPONSE_SCHEMA, contracts.FIELD_SCHEMA, contracts.DECIMAL_SCHEMA,
        contracts.UNIT_SCHEMA, contracts.MEASUREMENT_SCHEMA, contracts.EVIDENCE_SCHEMA,
    ]
    for relative in schema_paths:
        value = load_json(root / relative)
        strict_schema(value, relative)
        schemas[relative] = value
    require(len(schemas) == 6, "strict schema count differs")
    require(len({value["title"] for value in schemas.values()}) == 6, "schema titles are not unique")

    fixture_path = root / contracts.NEW_SOURCE_PATHS[4]
    fixture = load_json(fixture_path)
    require(fixture_path.read_bytes() == contracts.canonical(fixture) + b"\n", "fixture is not canonical sorted JSON plus LF")
    require(fixture["schema"] == "V21P03C03TypedResponseCorpusV1" and fixture["schemaVersion"] == 1 and fixture["testOnly"] is True, "fixture identity differs")
    require(fixture["responseKinds"] == sorted(contracts.RESPONSE_KINDS), "fixture response kinds differ")
    require(fixture["unitIDs"] == contracts.UNIT_IDS, "fixture unit IDs differ")
    require(fixture["measurementDimensions"] == sorted(contracts.MEASUREMENT_DIMENSIONS), "fixture dimensions differ")
    require(fixture["repeatActivities"] == contracts.ACTIVITY_VALUES, "fixture repeat activities differ")
    require(fixture["historicReleaseSHA256"] == "6b5d1129bbc81f9d0845323008ca348739d9b31ce541a48311a65a6f7adfac23", "historic release hash differs")
    require(fixture["historicBindingSHA256"] == "94cb18574feb493518ec00b28d982599a92e73a0d5ed465175d4d947c1914fc3", "historic binding hash differs")
    lifecycle = fixture["lifecycle"]
    require(
        lifecycle == {
            "backupRestoreRequired": False,
            "deleteEraseRequired": False,
            "downgradePolicy": "DORMANT_REVERT_ALLOWED",
            "exportReportRequired": False,
            "migrationRequired": False,
            "mode": "DECLARATION_ONLY",
            "persistent": False,
            "schema": "KERNEL_RESPONSE_V1",
            "searchRebuildReplayRequired": False,
        },
        "fixture lifecycle differs",
    )

    test_text = (root / contracts.NEW_SOURCE_PATHS[3]).read_text(encoding="utf-8")
    methods = re.findall(r"\bfunc\s+(testV9_13[A-Za-z0-9_]*)\s*\(", test_text)
    expected_methods = [
        "testV9_13G01EveryClosedResponseKindRoundTripsCanonically",
        "testV9_13A01UnitsDimensionsRangesPrecisionAndUnknownKindsFailClosed",
        "testV9_13H01RepeatIdentitySurvivesReorderResumeAndRejectsCollisions",
        "testV9_13I01InterruptedDormantContractPublicationExposesZeroOrCompleteRegistry",
        "testV9_13R01LegacySignParityAndDormantRecoveryPreserveExactSemantics",
    ]
    require(methods == expected_methods, f"named tests differ: {methods}")

    response = (root / contracts.NEW_SOURCE_PATHS[0]).read_text(encoding="utf-8")
    measurement = (root / contracts.NEW_SOURCE_PATHS[1]).read_text(encoding="utf-8")
    fields = (root / contracts.NEW_SOURCE_PATHS[2]).read_text(encoding="utf-8")
    adapter = (root / contracts.EXISTING_PATHS[3]).read_text(encoding="utf-8")
    workflow = "\n".join((root / path).read_text(encoding="utf-8") for path in contracts.EXISTING_PATHS[:3])
    require(not re.search(r"\b(?:Float|Double)\b|\[String\s*:\s*Any\]|AnyCodable|JSONSerialization", response + measurement + fields), "opaque or floating persistence token found")
    require("case contentReference(ResponseContentReferenceIDV1)" in response and "ContentReferenceV1 object" in response, "C05 content-reference boundary differs")
    require("noFloatPersistence = true" in measurement and "TIES_TO_EVEN_V1" in measurement, "exact rounding/float exclusion declaration missing")
    require("precisionScale == enteredValue.scale" in measurement, "entered precision is not preserved")
    require("canonicalOrder" in fields and "duplicateIdentity" in fields and "REACTIVATION_REVIEW_REQUIRED" in fields, "repeat identity closure missing")
    require("ResponseFieldValidatorV1.validateCollection" in workflow and "init(responseValue: ResponseValueV1)" in workflow, "workflow typed-response integration missing")
    require("ShippingIlluminatedSignAdapter" not in workflow and "SignPack" not in workflow, "sign branch leaked into neutral kernel")
    for token in [
        "LegacySignTypedResponseMappingV1", "acknowledgementValues", "couldNotVerifyFrozenDisplay",
        "shippingPackCanonicalSHA256", "inventedMeasurementCount", "typedResponses",
    ]:
        require(token in adapter, f"legacy adapter token missing: {token}")
    require("inventedMeasurementCount: 0" in adapter, "legacy adapter invents measurement truth")

    manifest = load_json(root / contracts.MANIFEST)
    require(manifest["cardID"] == contracts.CARD, "manifest card differs")
    require(manifest["pathFence"] == contracts.PATH_FENCE, "manifest fence differs")
    require(manifest["pathFenceCount"] == 24 and len(manifest["existingPaths"]) == 4 and len(manifest["newPaths"]) == 20, "manifest path counts differ")
    require(manifest["nativeCompileRan"] is False and manifest["hostedDispatchRan"] is False, "manifest overclaims native evidence")
    require(manifest["acceptanceCredit"] is False and manifest["releaseCredit"] is False, "manifest overclaims acceptance")
    require(manifest["phase10PollingDuringParallelExecution"] is False, "manifest claims Phase 10 polling")

    return {
        "result": "PASS",
        "cardID": contracts.CARD,
        "pathFenceCount": len(contracts.PATH_FENCE),
        "changedPathCount": len(observed),
        "strictSchemaCount": len(schemas),
        "namedStaticTestCount": len(methods),
        "fixtureSHA256": sha(fixture_path.read_bytes()),
        "manifestSHA256": sha((root / contracts.MANIFEST).read_bytes()),
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "phase10PollingDuringParallelExecution": False,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"V23-P03-C03 hostile verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

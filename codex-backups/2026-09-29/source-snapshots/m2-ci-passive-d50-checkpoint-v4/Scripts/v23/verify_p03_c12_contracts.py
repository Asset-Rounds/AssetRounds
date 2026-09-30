#!/usr/bin/env python3
"""Fail-closed static verification for provisional V23-P03-C12."""
from __future__ import annotations

import ast
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
import p03_c12_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def digest_without(value: dict[str, Any], key: str) -> str:
    unsigned = {name: item for name, item in value.items() if name != key}
    return contracts.sha256(contracts.pretty(unsigned))


def source(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def require_tokens(text: str, tokens: list[str], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    require(not missing, f"{label} lacks required structure: {missing}")


def changed_paths(root: Path) -> set[str]:
    result = subprocess.run(["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"],
                            check=True, capture_output=True, text=True, encoding="utf-8")
    paths = set()
    for line in result.stdout.splitlines():
        raw = line[3:]
        if " -> " in raw:
            _, raw = raw.split(" -> ", 1)
        paths.add(raw.replace("\\", "/"))
    return paths


def schema_checks(root: Path) -> None:
    schema = load(root / contracts.SCHEMA_PATH)
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
            "schema dialect differs")
    require(schema.get("type") == "object" and schema.get("additionalProperties") is False,
            "schema root is not strict")
    require(schema.get("$defs", {}).get("case", {}).get("additionalProperties") is False,
            "schema case is not strict")
    portable_root = root / "Scripts/v21-contracts"
    sys.path.insert(0, str(portable_root))
    try:
        import portable_contract_validator_v1 as portable
        lock = portable.load_lock(root)
        registry = portable.load_registry(root, lock)
        base_uri = (root / contracts.SCHEMA_PATH).resolve().as_uri()
        meta = portable.validate_schema_against_official_meta(schema, registry, base_uri)
        require(meta["valid"], f"schema meta-validation differs: {meta['errors'][:5]}")
        fixture = load(root / contracts.FIXTURE_PATH)
        result = portable.validate_instance(fixture, schema, registry, base_uri)
        require(result["valid"], f"fixture schema validation differs: {result['errors'][:5]}")
    finally:
        sys.path.remove(str(portable_root))


def python_checks(root: Path) -> None:
    for relative in ("Scripts/v23/p03_c12_contracts.py", "Scripts/v23/generate_p03_c12_contracts.py",
                     "Scripts/v23/verify_p03_c12_contracts.py"):
        ast.parse(source(root, relative), filename=relative)
    require(len(contracts.PATH_FENCE) == len(set(contracts.PATH_FENCE)) == 50,
            "path fence count or uniqueness differs")
    require(len(contracts.EXISTING_PATHS) == 37 and len(contracts.NEW_PATHS) == 13 and
            set(contracts.EXISTING_PATHS) | set(contracts.NEW_PATHS) == set(contracts.PATH_FENCE) and
            not set(contracts.EXISTING_PATHS) & set(contracts.NEW_PATHS), "path partition differs")
    require(contracts.CONTEXT_DIGEST == "6f225b50a731e06f6dbd16622d86e6ebe145e3f53bec11ad654d4425f4a0619d" and
            contracts.FENCE_DIGEST == "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806",
            "authority digest differs")


def swift_checks(root: Path) -> None:
    contracts_source = source(root, contracts.PATH_FENCE[0])
    engine_source = source(root, contracts.PATH_FENCE[1])
    persistence_source = source(root, contracts.PATH_FENCE[2])
    test_source = source(root, contracts.SWIFT_TEST_PATH)
    require_tokens(contracts_source, ["RequirementEvaluationV1", "CompletionDecisionV1", "IntegrityFindingV1",
                                     "SATISFIED", "NOT_SATISFIED", "NOT_APPLICABLE", "UNKNOWN", "WAIVED"],
                   "requirement contracts")
    require_tokens(engine_source, ["RequirementEvaluationEngineV1", "evaluateAll", "completionDecision",
                                  "evaluatedRevision", "policySetSHA256", "validateWaiver", "lint"],
                   "evaluation engine")
    lowered = (contracts_source + engine_source).lower()
    require("completenessscore" not in lowered and "confidencescore" not in lowered and
            "aggregatescore" not in lowered, "opaque score surface present")
    require_tokens(persistence_source, ["RequirementAssurancePersistenceReleaseV1", "case v8 = 8",
                                       "predecessorSchemaVersion = 7", "RequirementAssuranceRow", "@Model"],
                   "persistence models")
    named = re.findall(r"\bfunc\s+(testV9_21(?:G01|A01|H01|I01|R01)[A-Za-z0-9_]*)\s*\(", test_source)
    require(named == contracts.TEST_METHODS, f"exact five selectors differ: {named}")
    require(len(named) == 5 and len(set(named)) == 5, "selector cardinality differs")

    lifecycle_sources = {
        path: source(root, path) for path in contracts.EXISTING_PATHS
        if path.endswith(".swift")
    }
    joined = "\n".join(lifecycle_sources.values())
    require_tokens(
        joined,
        ["PersistentSchemaV8", "V8BackupRequirementAssuranceRecordV1", "requirementAssurance"],
        "V8/records-schema-7 lifecycle",
    )
    require_tokens(joined, ["WorkspaceWriter", "MutationReceipt", "RequirementEvaluation"],
                   "one-writer closure")
    require_tokens(lifecycle_sources["FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift"],
                   ["replay", "checkpoint"], "C11 replay closure")
    require_tokens(joined, ["Backup", "Restore", "Delete", "Erase", "Report", "RequirementEvaluation"],
                   "lifecycle codec closure")
    require(not any("/Search/" in path for path in contracts.PATH_FENCE), "fifth search root entered fence")
    require("RequirementEvaluationSummaryView" not in joined and
            not any(path.startswith("FieldEvidenceApp/Features/") and "Requirement" in path
                    for path in contracts.NEW_PATHS), "unreachable UI artifact present")
    new_production = contracts_source + "\n" + engine_source + "\n" + persistence_source
    require("#if DEBUG" not in new_production and "FaultInjection" not in new_production and
            "TestHook" not in new_production, "release test hook entered production source")


def generated_checks(root: Path) -> None:
    expected = contracts.all_outputs(root)
    for relative, raw in expected.items():
        require((root / relative).is_file() and (root / relative).read_bytes() == raw,
                f"stale generated artifact: {relative}")
    contract = load(root / contracts.CONTRACT_PATH)
    evidence = load(root / contracts.EVIDENCE_PATH)
    brand = load(root / contracts.BRAND_PATH)
    manifest = load(root / contracts.MANIFEST_PATH)
    for value, key in ((contract, "artifactDigest"), (evidence, "artifactDigest"),
                       (brand, "artifactDigest"), (manifest, "artifactDigest")):
        require(value[key] == digest_without(value, key), f"self digest differs: {value.get('schema')}")
    require(contract["pathFence"] == contracts.PATH_FENCE and
            contract["persistentContract"]["activeStoreSchemaVersion"] == 8 and
            contract["persistentContract"]["releasedRecordSchemaVersion"] == 7 and
            contract["evaluation"]["opaqueAggregateScoreAllowed"] is False and
            contract["siteExit"]["bypassAllowed"] is False, "contract semantics differ")
    required_posture = {
        "siteExitUIReachability": "NOT_RUN_NO_CREDIT_S10_RESERVED",
        "accessibility": "NOT_RUN_NO_CREDIT_S10_RESERVED",
        "universalFinalizationReachability": "NOT_PROVEN_S10_RESERVED",
        "completedSnapshotReachability": "NOT_PROVEN_S10_RESERVED",
        "codec": "PROVISIONAL_NONRELEASE_ONLY",
    }
    require(all(evidence.get(key) == value for key, value in required_posture.items()),
            "evidence provisional posture differs")
    require(brand["disposition"] == "NO_CURRENT_SHIPPING_UI_OR_BRAND_DELTA" and
            brand["affectedSurfacePaths"] == [] and brand["uiSurfaceDelta"] is False and
            brand["brandSurfaceDelta"] is False, "brand posture differs")
    require(manifest["manifestInputCount"] == len(manifest["artifacts"]) == 49 and
            manifest["artifactSetDigest"] == contracts.sha256(contracts.canonical(manifest["artifacts"])) and
            {row["path"] for row in manifest["artifacts"]} ==
            set(contracts.PATH_FENCE) - {contracts.MANIFEST_PATH}, "manifest closure differs")
    for row in manifest["artifacts"]:
        raw = (root / row["path"]).read_bytes()
        require(row["bytes"] == len(raw) and row["sha256"] == hashlib.sha256(raw).hexdigest(),
                f"manifest row differs: {row['path']}")
    for value in (contract, evidence, brand, manifest):
        for key in ("nativeCompileRan", "hostedDispatchEnabled", "hostedDispatchRan", "adoptionEnabled",
                    "acceptanceEnabled", "acceptanceCredit", "releaseCredit",
                    "phase10PollingDuringParallelExecution"):
            if key in value:
                require(value[key] is False, f"overclaim: {value.get('schema')}.{key}")
        require(value["requiresAcceptedS10_6Reconciliation"] is True,
                f"reconciliation differs: {value.get('schema')}")


def verify(root: Path) -> dict[str, Any]:
    python_checks(root)
    active_reserved = set(__import__("p03_c08_contracts").ACTIVE_S10_RESERVED_PATHS)
    require(len(active_reserved) == 86 and not set(contracts.PATH_FENCE) & active_reserved,
            "S10 reservation differs or overlaps")
    observed = changed_paths(root)
    require(observed and observed.issubset(set(contracts.PATH_FENCE)),
            f"changed path escaped fence: {sorted(observed - set(contracts.PATH_FENCE))}")
    require(all((root / path).is_file() for path in contracts.NEW_PATHS), "new path closure differs")
    schema_checks(root)
    swift_checks(root)
    generated_checks(root)
    require(not [path for path in root.rglob("*") if path.name == "__pycache__" or
                 path.suffix in (".pyc", ".pyo")], "Python cache leaked")
    return {
        "result": "PASS", "cardID": contracts.CARD, "verificationMode": "STATIC_ONLY",
        "pathFenceCount": 50, "existingPathCount": 37, "newPathCount": 13,
        "evidenceIDCount": 5, "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError,
            subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C12 static verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fail-closed verifier for the V23-P03-C27 static contract lane."""
from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c27_contracts as contracts


def strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key:{key}")
        result[key] = value
    return result


def changed_paths() -> set[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths = {
        line[3:].split(" -> ", 1)[-1].replace("\\", "/")
        for line in status.splitlines() if line
    }
    committed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths.update(path.replace("\\", "/") for path in committed.splitlines() if path)
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    failures: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
        rendered = contracts.all_outputs(ROOT)
    except Exception as error:
        rendered = {}
        failures.append(f"render:{error}")
    for relative, raw in rendered.items():
        path = ROOT / relative
        if not path.is_file() or path.read_bytes() != raw:
            failures.append(f"deterministic artifact:{relative}")
    for relative in (*contracts.SCRIPT_PATHS,):
        try:
            ast.parse((ROOT / relative).read_text(encoding="utf-8"), filename=relative)
        except (OSError, SyntaxError) as error:
            failures.append(f"python AST:{relative}:{error}")
    documents = {}
    for relative in contracts.GENERATED_PATHS:
        try:
            documents[relative] = json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=strict_object)
        except (OSError, ValueError, json.JSONDecodeError) as error:
            failures.append(f"strict JSON:{relative}:{error}")
    contract = documents.get(contracts.CONTRACT_PATH, {})
    required = contract.get("requiredSemantics", {}) if isinstance(contract, dict) else {}
    if required.get("resolutionOutcomes") != list(contracts.RESOLUTION_OUTCOMES) or len(contracts.RESOLUTION_OUTCOMES) != 8:
        failures.append("exact eight outcomes")
    if required.get("fiveSelectors") != list(contracts.TEST_METHODS) or len(contracts.TEST_METHODS) != 5:
        failures.append("exact five selectors")
    persistence = contract.get("persistence", {}) if isinstance(contract, dict) else {}
    for key, value in (("persistentSchemaVersion", 26), ("recordsSchemaVersion", 25),
                       ("persistentKindLifecycleModelCount", 94), ("durableFamilyCount", 2)):
        if persistence.get(key) != value:
            failures.append(f"persistence:{key}")
    if documents.get(contracts.MANIFEST_PATH, {}).get("statusFlags") != contracts.FLAGS or any(contracts.FLAGS.values()):
        failures.append("all static flags false")
    changed = changed_paths()
    unowned = sorted(changed - set(contracts.PATH_FENCE))
    if unowned:
        failures.append("changed path outside C27 fence:" + ",".join(unowned))
    if args.complete:
        missing = sorted(set(contracts.PATH_FENCE) - changed)
        if missing:
            failures.append("required C27 path missing:" + ",".join(missing))
    source = ROOT / "FieldEvidenceApp/Domain/AssetSemantics/AssetLocatorContractsV1.swift"
    if source.is_file():
        text = source.read_text(encoding="utf-8")
        for token in contracts.CONTRACT_NAMES:
            if re.search(rf"\b{re.escape(token)}\b", text) is None:
                failures.append(f"contract token:{token}")
    try:
        contracts.assert_corpus(ROOT)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        failures.append(f"corpus:{error}")
    cache_paths = sorted(path.as_posix() for path in (ROOT / "Scripts/v23").rglob("__pycache__"))
    cache_paths += sorted(path.as_posix() for path in (ROOT / "Scripts/v23").rglob("*.pyc"))
    if cache_paths:
        failures.append("python cache:" + ",".join(cache_paths))
    payload = {"cardID": contracts.CARD, "result": "PASS" if not failures else "FAIL",
               "complete": args.complete, "fencePathCount": len(contracts.PATH_FENCE),
               "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS),
               "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT,
               "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT, "failures": failures}
    if args.json:
        print(json.dumps(payload, sort_keys=True, indent=2))
    else:
        print(f"C27 verifier {payload['result']}: {len(failures)} failure(s)")
        for failure in failures:
            print(f"- {failure}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

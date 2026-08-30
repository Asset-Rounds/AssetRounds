#!/usr/bin/env python3
"""Fail-closed static verifier for V23-P04-C01 tooling artifacts."""
from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c01_contracts as contracts


def _run(arguments: list[str]) -> str:
    return subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, check=True).stdout


def _cache_paths() -> list[str]:
    scripts = ROOT / "Scripts/v23"
    values: list[str] = []
    if scripts.is_dir():
        for path in scripts.rglob("*"):
            if path.name == "__pycache__" or path.suffix == ".pyc":
                values.append(str(path.relative_to(ROOT)).replace("\\", "/"))
    return sorted(values)


def _fresh_outputs() -> dict[str, bytes]:
    code = (
        "import base64,json,sys;sys.dont_write_bytecode=True;sys.path.insert(0,'Scripts/v23');"
        "import p04_c01_contracts as c;print(json.dumps({k:base64.b64encode(v).decode('ascii') for k,v in c.all_outputs(c.Path('.')).items()},sort_keys=True))"
    )
    raw = _run([sys.executable, "-B", "-c", code])
    return {key: base64.b64decode(value) for key, value in json.loads(raw).items()}


def _verify_manifest(outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    try:
        manifest = json.loads(outputs[contracts.MANIFEST_PATH].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        expected_rows = []
        for path in contracts.MANIFEST_INPUT_PATHS:
            if path in outputs:
                data = outputs[path]
                expected_rows.append({"path": path, "byteCount": len(data), "sha256": hashlib.sha256(data).hexdigest(), "status": "SEALED_TOOLING"})
            elif (ROOT / path).is_file():
                data = (ROOT / path).read_bytes()
                expected_rows.append({"path": path, "byteCount": len(data), "sha256": hashlib.sha256(data).hexdigest(), "status": "SEALED_TOOLING" if path in contracts.TOOLING_EDIT_PATHS else "SEALED_SOURCE"})
            else:
                expected_rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"})
        if manifest.get("files") != expected_rows:
            failures.append("manifest byte inventory differs")
        for key, expected in (("pathFence", list(contracts.PATH_FENCE)), ("existingPaths", list(contracts.EXISTING_PATHS)), ("newPaths", list(contracts.NEW_PATHS)), ("toolingEditPaths", list(contracts.TOOLING_EDIT_PATHS))):
            if manifest.get(key) != expected:
                failures.append("manifest " + key + " differs")
        for key, expected in (("existingPathCount", len(contracts.EXISTING_PATHS)), ("newPathCount", len(contracts.NEW_PATHS)), ("fencePathCount", len(contracts.PATH_FENCE)), ("manifestInputCount", len(contracts.MANIFEST_INPUT_PATHS))):
            if manifest.get(key) != expected:
                failures.append("manifest " + key + " differs")
        if manifest.get("finalHashesSealed") is not contracts.FINAL_HASHES_SEALED:
            failures.append("manifest finalHashesSealed differs")
        expected_disposition = "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
        if manifest.get("hashDisposition") != expected_disposition:
            failures.append("manifest hash disposition differs")
        if any(row.get("path") == contracts.MANIFEST_PATH for row in manifest.get("files", [])):
            failures.append("manifest self included")
        if contracts.FINAL_HASHES_SEALED:
            expected_set = hashlib.sha256(contracts.canonical(expected_rows)).hexdigest()
            if manifest.get("artifactSetDigest") != expected_set:
                failures.append("manifest artifact set digest differs")
            without = dict(manifest)
            without.pop("artifactDigest", None)
            if manifest.get("artifactDigest") != hashlib.sha256(contracts.pretty(without)).hexdigest():
                failures.append("manifest artifact digest differs")
            if any(row.get("status") not in ("SEALED_SOURCE", "SEALED_TOOLING") or row.get("sha256") is None for row in manifest.get("files", [])):
                failures.append("sealed manifest contains pending row")
        elif manifest.get("artifactSetDigest") is not None or manifest.get("artifactDigest") is not None:
            failures.append("provisional manifest carries a sealed digest")
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        failures.append("manifest parse/validation:" + str(exc))
    return failures


def _verify_json_outputs(outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    for path in contracts.OUTPUT_PATHS:
        try:
            json.loads(outputs[path].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        except (KeyError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
            failures.append(path + ":invalid JSON:" + str(exc))
    return failures


def verify(complete: bool = False) -> dict[str, Any]:
    failures: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
    except Exception as exc:
        failures.append("scaffold:" + str(exc))
    for path in contracts.SCRIPT_PATHS:
        target = ROOT / path
        if not target.is_file():
            failures.append("missing script:" + path)
            continue
        try:
            ast.parse(target.read_text(encoding="utf-8"), filename=path)
        except SyntaxError as exc:
            failures.append("AST:" + path + ":" + str(exc))
    status = contracts.source_status(ROOT)
    selectors = tuple(status.get("selectors", ()))
    if complete:
        try:
            selectors = contracts.assert_source_contracts(ROOT)
        except Exception as exc:
            failures.append("source:" + str(exc))
    try:
        outputs = contracts.all_outputs(ROOT)
        stale = [path for path, data in outputs.items() if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != data]
        if stale:
            failures.append("stale generated outputs:" + ",".join(stale))
        failures.extend(_verify_json_outputs(outputs))
        failures.extend(_verify_manifest(outputs))
    except Exception as exc:
        outputs = {}
        failures.append("outputs:" + str(exc))
    try:
        fresh = _fresh_outputs()
        if outputs and fresh != outputs:
            failures.append("fresh-process output differs")
    except Exception as exc:
        failures.append("fresh-process:" + str(exc))
    changed = contracts.observed_changed_paths(ROOT)
    changed_set = set(changed)
    fence_set = set(contracts.PATH_FENCE)
    new_set = set(contracts.NEW_PATHS)
    fenced_changed = sorted(changed_set & fence_set)
    unchanged_existing = sorted(set(contracts.EXISTING_PATHS) - changed_set)
    missing_new = sorted(new_set - changed_set)
    unowned = sorted(changed_set - fence_set)
    if unowned:
        failures.append("unowned changed paths:" + ",".join(unowned))
    if complete and missing_new:
        failures.append("incomplete C01 fence; missing changed new paths:" + ",".join(missing_new))
    if complete and not contracts.FINAL_HASHES_SEALED:
        failures.append("complete verification requires final hashes sealed")
    if _cache_paths():
        failures.append("bytecode/cache artifacts present")
    if contracts.FLAGS != {name: False for name in contracts.FLAGS}:
        failures.append("activation/native/hosted/adoption/acceptance/release flags are not all false")
    result = {
        "cardID": contracts.CARD, "complete": complete, "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC",
        "failures": failures, "sourceReady": bool(status["hydrated"]), "sourceMissing": status["missingPaths"],
        "selectors": list(selectors), "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS),
        "fencePathCount": len(contracts.PATH_FENCE), "changedPathCount": len(changed), "fencedChangedPathCount": len(fenced_changed),
        "newChangedPathCount": len(new_set & changed_set), "unchangedExistingPathCount": len(unchanged_existing),
        "missingNewPathCount": len(missing_new), "unownedChangedPathCount": len(unowned),
        "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": contracts.S10_RESERVATION_OVERLAP_COUNT, "manifestInputCount": len(contracts.MANIFEST_INPUT_PATHS),
        "manifestSelfExcluded": True, "finalHashesSealed": contracts.FINAL_HASHES_SEALED,
        "flagsAllFalse": all(value is False for value in contracts.FLAGS.values()), "cachePaths": _cache_paths(),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = verify(args.complete)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        print(result["result"] + ("; " + "; ".join(result["failures"]) if result["failures"] else ""))
    return 0 if not result["failures"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

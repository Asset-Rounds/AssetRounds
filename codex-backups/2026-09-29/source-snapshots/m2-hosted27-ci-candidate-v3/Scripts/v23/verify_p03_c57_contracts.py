#!/usr/bin/env python3
"""Fail-closed static verifier for the V23-P03-C57 MyDay tooling lane."""
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

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c57_contracts as contracts


def _run(arguments: list[str]) -> str:
    return subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, check=True).stdout


def _cache_paths() -> list[str]:
    values: list[str] = []
    scripts = ROOT / "Scripts/v23"
    for path in scripts.rglob("*") if scripts.is_dir() else ():
        if path.name == "__pycache__" or path.suffix == ".pyc":
            values.append(str(path.relative_to(ROOT)).replace("\\", "/"))
    return sorted(values)


def _fresh_outputs() -> dict[str, bytes]:
    code = ("import base64,json,sys;sys.dont_write_bytecode=True;sys.path.insert(0,'Scripts/v23');"
            "import p03_c57_contracts as c;print(json.dumps({k:base64.b64encode(v).decode('ascii') "
            "for k,v in c.all_outputs(c.Path('.')).items()},sort_keys=True))")
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
        if manifest.get("hashDisposition") != ("SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"):
            failures.append("manifest hash disposition differs")
        if any(row.get("path") == contracts.MANIFEST_PATH for row in manifest.get("files", [])):
            failures.append("manifest self included")
        if contracts.FINAL_HASHES_SEALED:
            expected_set = hashlib.sha256(contracts.canonical(expected_rows)).hexdigest()
            if manifest.get("artifactSetDigest") != expected_set:
                failures.append("manifest artifact set digest differs")
            without = dict(manifest); without.pop("artifactDigest", None)
            if manifest.get("artifactDigest") != hashlib.sha256(contracts.pretty(without)).hexdigest():
                failures.append("manifest artifact digest differs")
            if any(row.get("status") not in ("SEALED_SOURCE", "SEALED_TOOLING") or row.get("sha256") is None for row in manifest.get("files", [])):
                failures.append("sealed manifest contains pending row")
        else:
            if manifest.get("artifactSetDigest") is not None or manifest.get("artifactDigest") is not None:
                failures.append("provisional manifest contains final digest")
            if any(row.get("status") not in ("SEALED_SOURCE", "SEALED_TOOLING", "PENDING_SOURCE") for row in manifest.get("files", [])):
                failures.append("provisional manifest row status differs")
    except Exception as error:
        failures.append("manifest verification:" + str(error))
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true", help="require all C57 source rows and final sealing")
    parser.add_argument("--json", action="store_true", help="emit a structured result")
    args = parser.parse_args()
    failures: list[str] = []
    outputs: dict[str, bytes] = {}
    changed: set[str] = set()
    cache: list[str] = []
    selectors: tuple[str, ...] = ()
    try:
        contracts.assert_scaffold(ROOT)
        for path in contracts.SCRIPT_PATHS:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        if contracts.source_status(ROOT)["hydrated"]:
            selectors = contracts.assert_source_contracts(ROOT)
        outputs = contracts.all_outputs(ROOT)
    except Exception as error:
        failures.append(str(error))
    try:
        changed = set(contracts.observed_changed_paths(ROOT))
        cache = _cache_paths()
    except Exception as error:
        failures.append("change inventory:" + str(error))
    missing = [path for path in contracts.PATH_FENCE if not (ROOT / path).is_file()]
    if missing:
        failures.append("missing:" + ",".join(missing))
    for path, data in outputs.items():
        target = ROOT / path
        if not target.is_file() or target.read_bytes() != data:
            failures.append("artifact differs:" + path)
    if cache:
        failures.append("python cache:" + ",".join(cache))
    if any(contracts.FLAGS.values()):
        failures.append("status flags")
    fence_changed = changed & set(contracts.PATH_FENCE)
    new_changed = changed & set(contracts.NEW_PATHS)
    unowned = changed - set(contracts.PATH_FENCE)
    if unowned:
        failures.append("unowned changed path:" + ",".join(sorted(unowned)))
    if args.complete:
        missing_new = set(contracts.NEW_PATHS) - changed
        if missing_new:
            failures.append("missing changed new path:" + ",".join(sorted(missing_new)))
        if not selectors:
            failures.append("C57 source lanes unresolved")
        if not contracts.FINAL_HASHES_SEALED:
            failures.append("final sealing held")
        try:
            first, second = _fresh_outputs(), _fresh_outputs()
            if first != second or (outputs and first != outputs):
                failures.append("fresh-process generation is nondeterministic")
        except Exception as error:
            failures.append("fresh-process generation:" + str(error))
        if outputs:
            failures.extend(_verify_manifest(outputs))
    result = {
        "cardID": contracts.CARD, "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL", "complete": args.complete,
        "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS), "fencePathCount": len(contracts.PATH_FENCE),
        "expectedExistingPathCount": contracts.EXPECTED_EXISTING_PATH_COUNT, "expectedNewPathCount": contracts.EXPECTED_NEW_PATH_COUNT, "expectedFencePathCount": contracts.EXPECTED_FENCE_PATH_COUNT,
        "changedPathCount": len(changed), "fenceChangedPathCount": len(fence_changed), "newChangedPathCount": len(new_changed), "unchangedExistingPathCount": len(set(contracts.EXISTING_PATHS) - changed),
        "missingPathCount": len(missing), "unownedChangedPathCount": len(unowned), "pythonCachePathCount": len(cache), "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "sourceReady": bool(selectors), "selectorCount": len(selectors), "flagsAllFalse": not any(contracts.FLAGS.values()), "finalHashesSealed": contracts.FINAL_HASHES_SEALED, "failures": failures,
    }
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else result["result"])
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

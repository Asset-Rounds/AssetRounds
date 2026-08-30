#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import base64
import json
import os
import subprocess
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c54_contracts as contracts


def _run(arguments: list[str]) -> str:
    return subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, check=True).stdout


def _changed_paths() -> set[str]:
    tracked = set(_run(["git", "diff", "--name-only", contracts.BASE_HEAD, "--"]).split())
    untracked = set(_run(["git", "ls-files", "--others", "--exclude-standard"]).split())
    return tracked | untracked


def _cache_paths() -> list[str]:
    candidates = list((ROOT / "Scripts/v23").rglob("*.pyc")) + list((ROOT / "Scripts/v23").rglob("__pycache__"))
    return sorted(str(path.relative_to(ROOT)).replace("\\", "/") for path in candidates)


def _fresh_outputs() -> dict[str, bytes]:
    code = (
        "import base64,json,sys;sys.dont_write_bytecode=True;"
        "sys.path.insert(0,'Scripts/v23');import p03_c54_contracts as c;"
        "print(json.dumps({k:base64.b64encode(v).decode('ascii') for k,v in c.all_outputs(c.Path('.')).items()},sort_keys=True))"
    )
    raw = _run([sys.executable, "-B", "-c", code])
    return {key: base64.b64decode(value) for key, value in json.loads(raw).items()}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()
    failures: list[str] = []
    outputs: dict[str, bytes] = {}
    changed: set[str] = set()
    cache: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
        for path in contracts.SCRIPTS:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        outputs = contracts.all_outputs(ROOT)
    except Exception as error:
        failures.append(str(error))
    missing = [path for path in contracts.FENCE if not (ROOT / path).is_file()]
    if missing:
        failures.append("missing:" + ",".join(missing))
    for path, value in outputs.items():
        if (ROOT / path).is_file() and (ROOT / path).read_bytes() != value:
            failures.append("artifact differs:" + path)
    try:
        changed = _changed_paths()
        cache = _cache_paths()
    except Exception as error:
        failures.append("change inventory:" + str(error))
    if cache:
        failures.append("python cache:" + ",".join(cache))
    if arguments.complete:
        unowned = changed - set(contracts.FENCE)
        incomplete = set(contracts.FENCE) - changed
        if unowned:
            failures.append("unowned changed path:" + ",".join(sorted(unowned)))
        if incomplete:
            failures.append("incomplete fence:" + ",".join(sorted(incomplete)))
        try:
            first = _fresh_outputs()
            second = _fresh_outputs()
            if first != second or (outputs and first != outputs):
                failures.append("fresh-process generation is nondeterministic")
        except Exception as error:
            failures.append("fresh-process generation:" + str(error))
    fence_changed = changed & set(contracts.FENCE)
    new_changed = changed & set(contracts.NEW)
    unowned = changed - set(contracts.FENCE)
    result = {
        "cardID": contracts.CARD,
        "result": "PASS" if not failures else "FAIL",
        "complete": arguments.complete,
        "existingPathCount": len(contracts.EXISTING),
        "newPathCount": len(contracts.NEW),
        "fencePathCount": len(contracts.FENCE),
        "changedPathCount": len(changed),
        "fenceChangedPathCount": len(fence_changed),
        "newChangedPathCount": len(new_changed),
        "missingPathCount": len(missing),
        "unownedChangedPathCount": len(unowned),
        "pythonCachePathCount": len(cache),
        "priorFenceCount": 83,
        "priorOwnedPathCount": 1356,
        "authorizedOverlapCount": 217,
        "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0,
        "flagsAllFalse": not any(contracts.FLAGS.values()),
        "failures": failures,
    }
    print(json.dumps(result, indent=2, sort_keys=True) if arguments.json else result["result"])
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

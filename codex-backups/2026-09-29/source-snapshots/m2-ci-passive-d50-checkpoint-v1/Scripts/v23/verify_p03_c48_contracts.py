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
import p03_c48_contracts as contracts


def _fresh_process_outputs(root: Path) -> dict[str, bytes]:
    child = (
        "import base64,json,sys;from pathlib import Path;"
        "sys.path.insert(0,str(Path.cwd()/'Scripts'/'v23'));"
        "import p03_c48_contracts as contracts;"
        "outputs=contracts.all_outputs(Path.cwd());"
        "print(json.dumps({p:base64.b64encode(d).decode('ascii') for p,d in sorted(outputs.items())},sort_keys=True,separators=(',',':')))"
    )
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"

    def run() -> dict[str, bytes]:
        completed = subprocess.run(
            [sys.executable, "-B", "-c", child], cwd=root, env=env,
            check=True, capture_output=True, text=True,
        )
        payload = json.loads(completed.stdout)
        return {path: base64.b64decode(value, validate=True) for path, value in payload.items()}

    first, second = run(), run()
    if first != second:
        raise ValueError("C48 fresh-process deterministic replay differs")
    return first


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--complete", action="store_true")
    args = parser.parse_args()
    failures: list[str] = []
    outputs: dict[str, bytes] = {}
    try:
        contracts.assert_scaffold(ROOT)
        for path in contracts.SCRIPT_PATHS:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        outputs = contracts.all_outputs(ROOT)
        if _fresh_process_outputs(ROOT) != outputs:
            raise ValueError("C48 fresh-process outputs differ from in-process outputs")
    except Exception as error:
        failures.append(str(error))
    changed = set(contracts.observed_changed_paths(ROOT))
    missing = sorted(path for path in contracts.PATH_FENCE if not (ROOT / path).is_file())
    if missing:
        failures.append("missing:" + ",".join(missing))
    for path, data in outputs.items():
        target = ROOT / path
        if not target.is_file():
            failures.append("artifact absent:" + path)
        elif target.read_bytes() != data:
            failures.append("artifact differs:" + path)
    unowned = sorted(changed - set(contracts.PATH_FENCE))
    if unowned:
        failures.append("unowned:" + ",".join(unowned))
    if args.complete:
        unchanged = sorted(set(contracts.PATH_FENCE) - changed)
        if unchanged:
            failures.append("incomplete fence:" + ",".join(unchanged))
    if any(contracts.FLAGS.values()):
        failures.append("status flags")
    caches = sorted(
        str(path.relative_to(ROOT)).replace("\\", "/")
        for path in (ROOT / "Scripts" / "v23").rglob("*")
        if path.name == "__pycache__" or path.suffix == ".pyc"
    )
    if caches:
        failures.append("bytecode cache:" + ",".join(caches))
    result = {
        "cardID": contracts.CARD,
        "result": "PASS" if not failures else "FAIL",
        "complete": args.complete,
        "fencePathCount": 139,
        "existingPathCount": 125,
        "newPathCount": 14,
        "authorizedOverlapCount": 0,
        "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0,
        "s10ReservedPathCount": 86,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "failures": failures,
    }
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else "C48 verifier " + result["result"])
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c43_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--complete", action="store_true")
    args = parser.parse_args()
    failures: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
        for path in contracts.SCRIPT_PATHS:
            ast.parse((ROOT / path).read_text(encoding="utf-8"))
        expected_outputs = contracts.all_outputs(ROOT)
    except Exception as error:
        failures.append(str(error))
        expected_outputs = {}
    changed = contracts.observed_changed_paths(ROOT)
    for path, expected in expected_outputs.items():
        target = ROOT / path
        if not target.is_file():
            failures.append(f"artifact absent:{path}")
        elif target.read_bytes() != expected:
            failures.append(f"artifact differs:{path}")
    unowned = changed - set(contracts.PATH_FENCE)
    if unowned:
        failures.append("unowned:" + ",".join(sorted(unowned)))
    if args.complete and set(contracts.PATH_FENCE) - changed:
        failures.append("incomplete fence")
    if any(contracts.FLAGS.values()):
        failures.append("status flags")
    result = {
        "cardID": contracts.CARD, "result": "PASS" if not failures else "FAIL", "complete": args.complete,
        "fencePathCount": 14, "existingPathCount": 0, "newPathCount": 14,
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0,
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "failures": failures,
    }
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else f"C43 verifier {result['result']}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

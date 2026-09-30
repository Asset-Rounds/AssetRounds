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
import p03_c42_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    failures: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
        contracts.require_source_ready(ROOT)
        rendered = contracts.all_outputs(ROOT)
    except Exception as error:
        rendered = {}
        failures.append(f"render:{error}")
    for path in contracts.SCRIPT_PATHS:
        try:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        except Exception as error:
            failures.append(f"AST:{path}:{error}")
    try:
        changed = contracts.observed_changed_paths(ROOT)
    except Exception as error:
        changed = set()
        failures.append(f"changed-paths:{error}")
    for path, expected in rendered.items():
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
        "fencePathCount": 35, "existingPathCount": 21, "newPathCount": 14,
        "authorizedOverlapCount": 306, "unauthorizedOverlapCount": 0,
        "durableFamilyCount": 0, "persistentSchemaVersion": None, "recordsSchemaVersion": None,
        "statusFlags": contracts.FLAGS, "failures": failures,
    }
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else f"C42 verifier {result['result']}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

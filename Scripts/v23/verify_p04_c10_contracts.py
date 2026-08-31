#!/usr/bin/env python3
"""Fail-closed verifier for V23-P04-C10 tooling and source closure."""
import argparse
import ast
import json
import os
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c10_contracts as c

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true", help="require complete source lanes and sealed hashes")
    parser.add_argument("--json", action="store_true", help="emit machine-readable evidence")
    args = parser.parse_args()
    failures = []
    try:
        c.authority()
    except Exception as error:
        failures.append("authority:" + str(error))
    for path in c.SCRIPT_PATHS:
        try:
            ast.parse((c.ROOT / path).read_text(encoding="utf-8"), path)
        except Exception as error:
            failures.append("syntax:" + path + ":" + str(error))
    try:
        expected = {path: c.pretty(value) for path, value in c.documents().items()}
        c.validate_generated_documents({path: json.loads(data) for path, data in expected.items()})
        for path, data in expected.items():
            if not (c.ROOT / path).is_file() or (c.ROOT / path).read_bytes() != data:
                failures.append("artifact-drift:" + path)
        rows, ready = c.source_rows()
        c.validate_source_semantics(rows, ready)
        owned, counts = c.fence_rows()
        if len(owned) != 113 or counts["s10ReservationOverlapCount"] != 0:
            failures.append("fence:owned count or S10 overlap differs")
        if counts["unownedChangedPathCount"] != 0:
            failures.append("fence:unowned changed paths present")
        if args.complete and (not ready or not c.FINAL_HASHES_SEALED):
            failures.append("complete:source lanes or owner-directed sealing pending")
    except Exception as error:
        failures.append("contracts:" + str(error))
        ready = False
        counts = {}
    report = {
        "cardID": c.CARD,
        "result": "FAIL_STATIC" if failures else ("PASS_STATIC_SEALED" if c.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"),
        "complete": args.complete,
        "finalHashesSealed": c.FINAL_HASHES_SEALED,
        "sourceReady": ready,
        "failures": failures,
        "fencePathCount": 113,
        "existingPathCount": 97,
        "newPathCount": 16,
        "counts": counts,
        "selectors": list(c.SELECTORS),
        "flagsAllFalse": all(value is False for value in c.FLAGS.values()),
    }
    print(json.dumps(report, sort_keys=True, indent=2) if args.json else report["result"])
    return 1 if failures else 0

if __name__ == "__main__":
    raise SystemExit(main())

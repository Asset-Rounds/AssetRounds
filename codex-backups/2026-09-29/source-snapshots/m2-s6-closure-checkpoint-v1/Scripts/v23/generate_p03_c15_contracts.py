#!/usr/bin/env python3
"""Generate or check Card 52's deterministic static C15 artifacts."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c15_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write deterministic generated artifacts")
    parser.add_argument("--check", action="store_true", help="verify generated artifacts without writing")
    parser.add_argument("--dump-json", action="store_true", help="print generated artifact bytes as JSON")
    args = parser.parse_args()
    rendered = contracts.all_outputs(ROOT)
    if args.dump_json:
        print(json.dumps({path: raw.decode("utf-8") for path, raw in rendered.items()}, ensure_ascii=False, sort_keys=True, indent=2))
        return 0

    mismatches: list[str] = []
    for relative, expected in rendered.items():
        path = ROOT / relative
        if args.apply:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)
        elif not path.is_file():
            mismatches.append(f"missing:{relative}")
        elif path.read_bytes() != expected:
            mismatches.append(f"different:{relative}")
    if mismatches:
        print(json.dumps({"result": "FAIL_STATIC_PROVISIONAL", "mismatches": mismatches}, sort_keys=True))
        return 1
    print("PASS_STATIC_PROVISIONAL")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

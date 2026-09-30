#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c43_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.apply == args.check:
        parser.error("choose exactly one of --apply or --check")
    contracts.assert_scaffold(ROOT)
    outputs = contracts.all_outputs(ROOT)
    stale = [path for path, data in outputs.items() if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != data]
    if args.check:
        if stale:
            print("C43 generator stale: " + ",".join(stale))
            return 1
        print("C43 generator check PASS (5 artifacts)")
        return 0
    for path, data in outputs.items():
        target = ROOT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print("C43 generator wrote 5 artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

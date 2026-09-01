#!/usr/bin/env python3
"""Deterministically generate or check the five C37 tooling artifacts."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c37_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write all generated artifacts")
    parser.add_argument("--check", action="store_true", help="fail when any artifact is stale")
    args = parser.parse_args()
    if args.apply == args.check:
        parser.error("choose exactly one of --apply or --check")
    outputs = contracts.documents()
    stale = [path for path, value in outputs.items() if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != contracts.pretty(value)]
    if args.check:
        print(f"C37 generator check {'PASS_STATIC_PROVISIONAL' if not stale else 'FAIL'} generated={len(outputs)}")
        if stale:
            print("stale=" + ",".join(stale))
        return 0 if not stale else 1
    for path, value in outputs.items():
        target = ROOT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(contracts.pretty(value))
    print(f"C37 generator apply PASS_STATIC_PROVISIONAL generated={len(outputs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

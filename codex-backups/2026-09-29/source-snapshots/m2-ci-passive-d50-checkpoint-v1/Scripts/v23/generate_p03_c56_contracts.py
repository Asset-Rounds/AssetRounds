#!/usr/bin/env python3
"""Deterministic C56 tooling generator; final sealing is source-gated."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c56_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="write the five generated artifacts")
    parser.add_argument("--check", action="store_true", help="check the five generated artifacts")
    args = parser.parse_args()
    if args.apply == args.check:
        parser.error("choose exactly one of --apply or --check")

    outputs = contracts.all_outputs(ROOT)
    stale = [
        path for path, data in outputs.items()
        if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != data
    ]
    if args.check:
        if stale:
            print("C56 generator stale:" + ",".join(stale))
            return 1
        print("C56 generator check PASS_STATIC_PROVISIONAL")
        return 0

    for path, data in outputs.items():
        destination = ROOT / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    print("C56 generator apply PASS_STATIC_PROVISIONAL (input hashes sealed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

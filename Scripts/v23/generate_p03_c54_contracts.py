#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c54_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    if arguments.apply == arguments.check:
        parser.error("choose exactly one")
    outputs = contracts.all_outputs(ROOT)
    stale = [
        path
        for path, value in outputs.items()
        if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != value
    ]
    if arguments.check:
        print("C54 generator " + ("PASS" if not stale else "stale:" + ",".join(stale)))
        return 0 if not stale else 1
    for path, value in outputs.items():
        destination = ROOT / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

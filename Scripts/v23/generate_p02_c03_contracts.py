#!/usr/bin/env python3
"""Generate or check V23-P02-C03 deterministic provisional artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from p02_c03_contracts import all_outputs


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    outputs = all_outputs(root)
    stale: list[str] = []
    for relative, expected in outputs.items():
        path = root / relative
        if args.apply:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)
        elif not path.is_file() or path.read_bytes() != expected:
            stale.append(relative)
    if stale:
        print("stale generated artifacts:")
        for path in stale:
            print(f"  {path}")
        return 1
    print(f"{'generated' if args.apply else 'verified'} {len(outputs)} deterministic artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

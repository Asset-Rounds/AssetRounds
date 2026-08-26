#!/usr/bin/env python3
"""Generate or check V23-P02-C05 deterministic tooling artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from p02_c05_contracts import GENERATED_PATHS, all_outputs


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="write the generated artifacts")
    mode.add_argument("--check", action="store_true", help="fail if any generated artifact is stale")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        outputs = all_outputs(root)
    except (OSError, ValueError) as error:
        print(f"unable to generate sealed C05 artifacts: {error}", file=sys.stderr)
        return 1

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
        for relative in stale:
            print(f"  {relative}")
        return 1
    print(f"{'generated' if args.apply else 'verified'} {len(GENERATED_PATHS)} deterministic artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

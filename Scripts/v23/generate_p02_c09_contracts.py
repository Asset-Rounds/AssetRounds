#!/usr/bin/env python3
"""Apply or check deterministic Card 29 tooling artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from p02_c09_contracts import GENERATED_PATHS, all_outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--apply", action="store_true", help="write generated artifacts")
    modes.add_argument("--check", action="store_true", help="fail when artifacts are stale")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        outputs = all_outputs(root)
        for relative in GENERATED_PATHS:
            path = root / relative
            expected = outputs[relative]
            if args.apply:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(expected)
            elif not path.is_file() or path.read_bytes() != expected:
                print(f"stale generated artifact: {relative}", file=sys.stderr)
                return 1
    except (OSError, ValueError, KeyError) as error:
        print(f"Card29 generation failed: {error}", file=sys.stderr)
        return 1
    mode = "generated" if args.apply else "verified"
    print(f"Card29 {mode} {len(GENERATED_PATHS)} deterministic artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

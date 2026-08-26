#!/usr/bin/env python3
"""Generate or check canonical V23-P01-C05 static artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from p01_c05_contracts import ContractError, all_outputs


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        outputs = all_outputs(root)
    except (ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P01-C05 generation failed: {error}", file=sys.stderr)
        return 1
    stale = []
    for relative, expected in outputs.items():
        path = root / relative
        observed = path.read_bytes() if path.is_file() else None
        if observed != expected:
            stale.append(relative)
            if args.apply:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(expected)
    if args.check and stale:
        for path in stale:
            print(f"stale or missing: {path}", file=sys.stderr)
        return 1
    print(("updated" if args.apply else "verified") + f" {len(outputs)} generated artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

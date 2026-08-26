#!/usr/bin/env python3
"""Generate or check the deterministic V23-P01-C07 fixtures and contracts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from p01_c07_contracts import ContractError, all_outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="write canonical C07 fixtures and documents")
    mode.add_argument("--check", action="store_true", help="verify canonical C07 fixtures and documents are current")
    parser.add_argument("--root", type=Path, default=None, help="repository root (defaults to this checkout)")
    args = parser.parse_args()
    root = (args.root or Path(__file__).resolve().parents[2]).resolve()
    try:
        outputs = all_outputs(root)
    except (ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P01-C07 generation failed: {error}", file=sys.stderr)
        return 1

    stale: list[str] = []
    for relative, expected in outputs.items():
        path = root / relative
        observed = path.read_bytes() if path.is_file() else None
        if observed != expected:
            stale.append(relative)
            if args.apply:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(expected)
    if args.check and stale:
        for relative in stale:
            print(f"stale or missing: {relative}", file=sys.stderr)
        return 1
    action = "updated" if args.apply else "verified"
    print(f"{action} {len(outputs)} generated artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

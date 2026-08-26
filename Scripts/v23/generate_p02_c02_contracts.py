#!/usr/bin/env python3
"""Generate or check deterministic V23-P02-C02 tooling artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from p02_c02_contracts import ContractError, all_outputs


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path)
    args = parser.parse_args()
    root = (args.root or Path(__file__).resolve().parents[2]).resolve()
    try:
        outputs = all_outputs(root)
        stale = []
        for path, expected in outputs.items():
            item = root / path
            if args.apply:
                item.parent.mkdir(parents=True, exist_ok=True)
                item.write_bytes(expected)
            elif not item.is_file() or item.read_bytes() != expected:
                stale.append(path)
        if stale:
            raise ContractError("stale generated artifacts: " + ", ".join(stale))
    except (ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P02-C02 generation failed: {error}", file=sys.stderr)
        return 1
    print(f"{'wrote' if args.apply else 'verified'} {len(outputs)} generated artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

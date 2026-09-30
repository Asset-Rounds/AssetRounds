#!/usr/bin/env python3
"""Write or byte-check Card 35 deterministic finding-lifecycle artifacts."""
from __future__ import annotations
import argparse
import sys
from pathlib import Path
sys.dont_write_bytecode = True
from p03_c04_contracts import ContractError, GENERATED_PATHS, all_outputs

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--apply", action="store_true")
    modes.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        outputs = all_outputs(root)
        stale = []
        for relative in GENERATED_PATHS:
            path = root / relative
            expected = outputs[relative]
            if args.apply:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(expected)
            elif not path.is_file() or path.read_bytes() != expected:
                stale.append(relative)
        if stale:
            raise ContractError("stale generated artifacts: " + ", ".join(stale))
    except (ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P03-C04 generation failed: {error}", file=sys.stderr)
        return 1
    print(f"V23-P03-C04 {'wrote' if args.apply else 'verified'} {len(GENERATED_PATHS)} deterministic artifacts")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

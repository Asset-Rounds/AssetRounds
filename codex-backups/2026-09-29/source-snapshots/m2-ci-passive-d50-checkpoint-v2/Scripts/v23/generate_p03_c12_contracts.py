#!/usr/bin/env python3
"""Generate or check the four deterministic V23-P03-C12 artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import p03_c12_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--apply", action="store_true")
    modes.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        outputs = contracts.all_outputs(root)
        if args.check:
            stale = [path for path, raw in outputs.items()
                     if not (root / path).is_file() or (root / path).read_bytes() != raw]
            if stale:
                raise contracts.ContractError("stale generated artifacts: " + ", ".join(stale))
        else:
            for relative, raw in outputs.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
    except (contracts.ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P03-C12 generation failed: {error}", file=sys.stderr)
        return 1
    print(f"V23-P03-C12 {'check' if args.check else 'generation'} PASS ({len(outputs)} artifacts)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

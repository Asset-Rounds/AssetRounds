#!/usr/bin/env python3
"""Generate or compare deterministic V23-P03-C16 evidence artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import p03_c16_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        outputs = contracts.all_outputs(root)
        differences = []
        for relative, expected in outputs.items():
            path = root / relative
            if args.check:
                if not path.is_file() or path.read_bytes() != expected:
                    differences.append(relative)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(expected)
        if differences:
            print("V23-P03-C16 generated artifacts differ: " + ", ".join(differences), file=sys.stderr)
            return 1
    except (OSError, UnicodeError, ValueError, contracts.ContractError) as error:
        print(f"V23-P03-C16 generation failed: {error}", file=sys.stderr)
        return 1
    print("V23-P03-C16 generated artifacts " + ("match" if args.check else "written"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

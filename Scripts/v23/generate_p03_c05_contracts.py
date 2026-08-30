#!/usr/bin/env python3
"""Generate or byte-check the C05 attempt-2 tooling projection."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c05_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--apply", action="store_true", help="write the deterministic outputs")
    modes.add_argument("--check", action="store_true", help="check output bytes without writing")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        outputs = contracts.all_outputs(root)
        differences = []
        for relative, expected in outputs.items():
            target = root / relative
            if args.apply:
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.is_file() or target.read_bytes() != expected:
                    target.write_bytes(expected)
            elif not target.is_file() or target.read_bytes() != expected:
                differences.append(relative)
        if args.check and differences:
            print("stale generated artifacts: " + ",".join(differences), file=sys.stderr)
            return 1
    except (contracts.ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"C05 generation failed: {error}", file=sys.stderr)
        return 1
    print({"cardID": contracts.CARD, "mode": "apply" if args.apply else "check", "artifactCount": len(outputs), "finalHashesSealed": contracts.FINAL_HASHES_SEALED})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

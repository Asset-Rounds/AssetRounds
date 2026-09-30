#!/usr/bin/env python3
"""Generate or check the four deterministic V23-P03-C11 JSON artifacts."""
from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import p03_c11_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--apply", action="store_true")
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--dump-json", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--root", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = args.root.resolve() if args.root else Path(__file__).resolve().parents[2]
    try:
        outputs = contracts.all_outputs(root)
        if set(outputs) != set(contracts.GENERATED_PATHS) or len(outputs) != 4:
            raise contracts.ContractError("exact four-output inventory differs")
        if args.dump_json:
            print(json.dumps(
                {path: base64.b64encode(value).decode("ascii")
                 for path, value in sorted(outputs.items())},
                sort_keys=True, separators=(",", ":"),
            ))
            return 0
        stale: list[str] = []
        for relative, expected in outputs.items():
            target = root / relative
            if args.apply:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(expected)
            elif not target.is_file() or target.read_bytes() != expected:
                stale.append(relative)
        if stale:
            raise contracts.ContractError(f"stale generated artifacts: {stale}")
    except (contracts.ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P03-C11 generation failed: {error}", file=sys.stderr)
        return 1
    print(f"V23-P03-C11 {'generated' if args.apply else 'verified'} 4 deterministic artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Generate or check the deterministic V23-P03-C06 contract artifacts."""
from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

import p03_c06_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--dump-json", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        generated_schemas = contracts.schemas()
        if set(generated_schemas) != set(contracts.SCHEMA_PATHS):
            raise contracts.ContractError("schema path inventory differs")
        if any(generated_schemas[path].get("x_assetrounds_productManifestDerived") is not True
               for path in contracts.PRODUCT_SCHEMA_PATHS):
            raise contracts.ContractError("product schema is not manifest-derived")
        if any(generated_schemas[path].get("x_assetrounds_productManifestDerived") is not False
               for path in contracts.TOOLING_SCHEMA_PATHS):
            raise contracts.ContractError("tooling schema classification differs")
        outputs = contracts.all_outputs(root)
        if set(outputs) != set(contracts.GENERATED_PATHS):
            raise contracts.ContractError("generated path inventory differs")
        if args.dump_json:
            print(json.dumps(
                {path: base64.b64encode(value).decode("ascii") for path, value in sorted(outputs.items())},
                sort_keys=True,
                separators=(",", ":"),
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
        print(f"V23-P03-C06 generation failed: {error}", file=sys.stderr)
        return 1
    verb = "generated" if args.apply else "verified"
    print(f"V23-P03-C06 {verb} {len(outputs)} deterministic artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

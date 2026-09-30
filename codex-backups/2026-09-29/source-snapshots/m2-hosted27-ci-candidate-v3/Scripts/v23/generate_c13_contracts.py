#!/usr/bin/env python3
"""Generate deterministic V23-P00-C13 coverage artifacts."""
from __future__ import annotations
import argparse
from pathlib import Path
from c13_contracts import MANIFEST_PATH, build_manifest, build_outputs, pretty_bytes

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(); root = args.root.resolve(); outputs = build_outputs(root)
    for relative, value in outputs.items():
        path = root / relative; expected = pretty_bytes(value)
        if args.check:
            if not path.is_file() or path.read_bytes() != expected: raise SystemExit(f"FAIL differs: {relative}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(expected)
    manifest = build_manifest(root); path = root / MANIFEST_PATH; expected = pretty_bytes(manifest)
    if args.check:
        if not path.is_file() or path.read_bytes() != expected: raise SystemExit(f"FAIL differs: {MANIFEST_PATH}")
    else: path.write_bytes(expected)
    print(f"PASS V23-P00-C13 generated={len(outputs) + 1} check={args.check}")
    return 0
if __name__ == "__main__": raise SystemExit(main())

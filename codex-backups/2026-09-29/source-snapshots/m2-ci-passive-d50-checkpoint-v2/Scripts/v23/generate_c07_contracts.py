#!/usr/bin/env python3
"""Generate or compare the exact V23-P00-C07 contract artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path

from c07_contracts import MANIFEST_PATH, build_manifest, build_outputs, pretty_bytes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path)
    args = parser.parse_args()
    root = (args.root or Path(__file__).resolve().parents[2]).resolve()
    outputs = build_outputs(root)
    for relative, value in outputs.items():
        path = root / relative
        expected = pretty_bytes(value)
        if args.check:
            if not path.is_file() or path.read_bytes() != expected:
                raise SystemExit(f"DIVERGENT: {relative}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)
    manifest = build_manifest(root)
    manifest_path = root / MANIFEST_PATH
    expected_manifest = pretty_bytes(manifest)
    if args.check:
        if not manifest_path.is_file() or manifest_path.read_bytes() != expected_manifest:
            raise SystemExit(f"DIVERGENT: {MANIFEST_PATH}")
    else:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_bytes(expected_manifest)
    print(f"PASS V23-P00-C07 generated={len(outputs) + 1} check={args.check}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Generate deterministic V23-P00-C11 concurrency artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path

from c11_contracts import MANIFEST_PATH, build_manifest, build_outputs, pretty_bytes


def write_or_check(root: Path, relative: str, value: object, check: bool) -> None:
    path = root / relative
    expected = pretty_bytes(value)
    if check:
        if not path.is_file() or path.read_bytes() != expected:
            raise SystemExit(f"DIVERGENT: {relative}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(expected)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve() if args.root else Path(__file__).resolve().parents[2]
    schemas, artifacts = build_outputs(root)
    for relative, value in {**schemas, **artifacts}.items():
        write_or_check(root, relative, value, args.check)
    manifest = build_manifest(root)
    write_or_check(root, MANIFEST_PATH, manifest, args.check)
    print(f"PASS V23-P00-C11 generated={len(schemas) + len(artifacts) + 1} check={args.check}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

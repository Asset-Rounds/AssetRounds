#!/usr/bin/env python3
"""Deterministically generate the five provisional C06 tooling artifacts."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c06_contracts as contracts  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write the generated artifact bytes")
    parser.add_argument("--check", action="store_true", help="check generated artifact bytes without writing")
    args = parser.parse_args()
    if args.apply == args.check:
        parser.error("choose exactly one of --apply or --check")

    rendered = contracts.outputs(ROOT)
    stale = [
        path for path, expected in rendered.items()
        if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != expected
    ]
    if args.check:
        result = "PASS_STATIC_SEALED" if contracts.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"
        print(f"C06 generator check {result}" if not stale else "C06 generator check FAIL_STATIC_STALE")
        if stale:
            print("stale=" + ",".join(stale))
        return 1 if stale else 0

    for path, data in rendered.items():
        destination = ROOT / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    result = "SEALED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL"
    print(f"C06 generator apply PASS_STATIC_{result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

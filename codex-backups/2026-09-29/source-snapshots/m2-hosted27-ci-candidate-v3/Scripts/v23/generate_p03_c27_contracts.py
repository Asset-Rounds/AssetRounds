#!/usr/bin/env python3
"""Generate or check deterministic V23-P03-C27 tooling artifacts."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c27_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--apply", action="store_true", help="write the five deterministic outputs")
    args = parser.parse_args()
    if args.check and args.apply:
        parser.error("--check and --apply are mutually exclusive")
    contracts.assert_scaffold(ROOT)
    rendered = contracts.all_outputs(ROOT)
    stale = [path for path, raw in rendered.items() if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != raw]
    if args.check:
        if stale:
            print("C27 generator check FAIL: " + ",".join(stale))
            return 1
        print(f"C27 generator check PASS ({len(rendered)} artifacts)")
        return 0
    if not args.apply:
        parser.error("use --apply to write artifacts or --check to verify them")
    for relative, raw in rendered.items():
        path = ROOT / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
    print(f"C27 generator wrote {len(rendered)} artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

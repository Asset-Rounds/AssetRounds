#!/usr/bin/env python3
from __future__ import annotations
import argparse, os, sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c51_contracts as contracts
C34_REPROOF_CARD = "V23-P03-C34"

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    assert contracts.C34_NAVIGATION_REPROOF["consumerCardID"] == C34_REPROOF_CARD
    if args.apply == args.check:
        parser.error("choose exactly one of --apply or --check")
    outputs = contracts.all_outputs(ROOT)
    stale = [p for p, data in outputs.items() if not (ROOT / p).is_file() or (ROOT / p).read_bytes() != data]
    if args.check:
        if stale:
            print("C51 generator stale:" + ",".join(stale)); return 1
        print("C51 generator check PASS (4 documents)"); return 0
    for path, data in outputs.items():
        target = ROOT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print("C51 generator wrote 4 documents")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Generate or check the deterministic V23-P03-C35 static artifacts."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import p03_c35_contracts as contracts

def main() -> int:
    parser=argparse.ArgumentParser()
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply",action="store_true")
    mode.add_argument("--check",action="store_true")
    mode.add_argument("--dump-json",action="store_true")
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    try: outputs=contracts.all_outputs(root)
    except (OSError,ValueError,json.JSONDecodeError) as error:
        print(f"{contracts.CARD} generation failed: {error}",file=sys.stderr); return 1
    if args.dump_json:
        print(json.dumps({path:raw.decode() for path,raw in outputs.items()},sort_keys=True)); return 0
    if args.check:
        stale=[path for path,raw in outputs.items() if not (root/path).is_file() or (root/path).read_bytes()!=raw]
        if stale: print("stale generated artifacts: "+", ".join(stale),file=sys.stderr); return 1
        print(json.dumps({"cardID":contracts.CARD,"result":"PASS","mode":"CHECK"},sort_keys=True)); return 0
    for relative,raw in outputs.items():
        path=root/relative; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(raw)
    print(json.dumps({"cardID":contracts.CARD,"result":"PASS","mode":"APPLY"},sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())

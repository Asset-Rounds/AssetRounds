#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path
from p01_c02_contracts import MANIFEST_PATH, build_manifest, build_outputs, pretty

def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[2]); parser.add_argument("--check",action="store_true")
    args=parser.parse_args(); root=args.root.resolve(); outputs=build_outputs(root)
    for rel,value in outputs.items():
        path=root/rel; data=pretty(value)
        if args.check:
            if not path.is_file() or path.read_bytes()!=data: print(f"FAIL differs: {rel}"); return 1
        else: path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data)
    manifest=build_manifest(root); path=root/MANIFEST_PATH; data=pretty(manifest)
    if args.check:
        if not path.is_file() or path.read_bytes()!=data: print(f"FAIL differs: {MANIFEST_PATH}"); return 1
    else: path.write_bytes(data)
    print(f"PASS V23-P01-C02 generated=4 check={args.check}"); return 0
if __name__=="__main__": raise SystemExit(main())

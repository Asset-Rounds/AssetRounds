#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path
from p01_c01_contracts import MANIFEST_PATH,build_manifest,build_outputs,pretty
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[2]);p.add_argument("--check",action="store_true");a=p.parse_args();root=a.root.resolve();outputs=build_outputs()
 for rel,value in outputs.items():
  path=root/rel;data=pretty(value)
  if a.check:
   if not path.is_file() or path.read_bytes()!=data:print(f"FAIL differs: {rel}");return 1
  else:path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
 manifest=build_manifest(root);path=root/MANIFEST_PATH;data=pretty(manifest)
 if a.check:
  if not path.is_file() or path.read_bytes()!=data:print(f"FAIL differs: {MANIFEST_PATH}");return 1
 else:path.write_bytes(data)
 print(f"PASS V23-P01-C01 generated=3 check={a.check}");return 0
if __name__=="__main__":raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations
import argparse,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c31_contracts as c
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true");p.add_argument("--check",action="store_true");a=p.parse_args()
 if a.apply==a.check:p.error("choose exactly one of --apply or --check")
 c.assert_scaffold(ROOT);outputs=c.all_outputs(ROOT);stale=[k for k,v in outputs.items() if not (ROOT/k).is_file() or (ROOT/k).read_bytes()!=v]
 if a.check:
  if stale:print("C31 generator stale: "+",".join(stale));return 1
  print("C31 generator check PASS (5 artifacts)");return 0
 for path,data in outputs.items():(ROOT/path).parent.mkdir(parents=True,exist_ok=True);(ROOT/path).write_bytes(data)
 print("C31 generator wrote 5 artifacts");return 0
if __name__=="__main__":raise SystemExit(main())

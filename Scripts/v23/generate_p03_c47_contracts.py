#!/usr/bin/env python3
from __future__ import annotations
import argparse,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c47_contracts as contracts
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true");p.add_argument("--check",action="store_true");a=p.parse_args()
 if a.apply==a.check:p.error("choose exactly one of --apply or --check")
 contracts.assert_scaffold(ROOT);outputs=contracts.all_outputs(ROOT);stale=[p for p,d in outputs.items() if not (ROOT/p).is_file() or (ROOT/p).read_bytes()!=d]
 if a.check:
  if stale:print("C47 generator stale: "+",".join(stale));return 1
  print("C47 generator check PASS (5 artifacts)");return 0
 for p,d in outputs.items():t=ROOT/p;t.parent.mkdir(parents=True,exist_ok=True);t.write_bytes(d)
 print("C47 generator wrote 5 artifacts");return 0
if __name__=="__main__":raise SystemExit(main())

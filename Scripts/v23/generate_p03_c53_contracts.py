#!/usr/bin/env python3
from __future__ import annotations
import argparse,os,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c53_contracts as c
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true");p.add_argument("--check",action="store_true");a=p.parse_args()
 if a.apply==a.check:p.error("choose exactly one")
 out=c.all_outputs(ROOT);stale=[path for path,value in out.items() if not (ROOT/path).is_file() or (ROOT/path).read_bytes()!=value]
 if a.check:print("C53 generator "+("PASS" if not stale else "stale:"+",".join(stale)));return 0 if not stale else 1
 for path,value in out.items():q=ROOT/path;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(value)
 return 0
if __name__=="__main__":raise SystemExit(main())

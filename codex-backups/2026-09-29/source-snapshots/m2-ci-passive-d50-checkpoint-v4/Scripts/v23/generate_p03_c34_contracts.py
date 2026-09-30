#!/usr/bin/env python3
import argparse,os,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c34_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true");p.add_argument("--check",action="store_true");a=p.parse_args()
 if a.apply==a.check:p.error("choose exactly one")
 out=c.all_outputs(Path(__file__).resolve().parents[2]);stale=[x for x,v in out.items() if not (Path(__file__).resolve().parents[2]/x).is_file() or (Path(__file__).resolve().parents[2]/x).read_bytes()!=v]
 if a.check:print("C34 generator " + ("PASS" if not stale else "stale:"+",".join(stale)));return 0 if not stale else 1
 for x,v in out.items():q=Path(__file__).resolve().parents[2]/x;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(v)
 return 0
if __name__=="__main__":raise SystemExit(main())

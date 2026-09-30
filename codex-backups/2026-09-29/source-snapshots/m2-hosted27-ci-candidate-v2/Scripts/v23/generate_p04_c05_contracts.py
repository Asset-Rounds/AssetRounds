#!/usr/bin/env python3
"""Deterministic generator for C05 tooling artifacts."""
from __future__ import annotations
import argparse,os,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c05_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true");p.add_argument("--check",action="store_true");a=p.parse_args()
 if a.apply==a.check:p.error("choose exactly one of --apply or --check")
 out=c.outputs(ROOT);stale=[x for x,b in out.items() if not(ROOT/x).is_file() or(ROOT/x).read_bytes()!=b]
 if a.check:print("C05 generator check "+("PASS_STATIC_SEALED" if c.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"));return 0 if not stale else 1
 for x,b in out.items():q=ROOT/x;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(b)
 print("C05 generator apply "+("PASS_STATIC_SEALED" if c.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"))
if __name__=="__main__":raise SystemExit(main() or 0)

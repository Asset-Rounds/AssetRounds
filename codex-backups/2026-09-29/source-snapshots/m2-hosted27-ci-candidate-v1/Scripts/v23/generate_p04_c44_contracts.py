#!/usr/bin/env python3
from __future__ import annotations
import argparse,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c44_contracts as c
def main():
 p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True);g.add_argument('--apply',action='store_true');g.add_argument('--check',action='store_true');a=p.parse_args()
 try:o=c.documents()
 except Exception as e:print(f'C44 generator FAIL_STATIC_AUTHORITY {e}');return 1
 stale=[]
 for path,v in o.items():
  t=ROOT/path;expected=c.pretty(v)
  if a.apply:t.parent.mkdir(parents=True,exist_ok=True);t.write_bytes(expected)
  elif not t.is_file() or t.read_bytes()!=expected:stale.append(path)
 if stale:print('C44 generator check FAIL_STATIC_STALE '+','.join(stale));return 1
 print(f"C44 generator {'apply' if a.apply else 'check'} PASS_STATIC_PROVISIONAL generated={len(o)}");return 0
if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations
import argparse,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c45_contracts as c
p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True);g.add_argument('--apply',action='store_true');g.add_argument('--check',action='store_true');a=p.parse_args()
try:o=c.documents()
except Exception as e:print('C45 generator FAIL_STATIC_AUTHORITY '+str(e));raise SystemExit(1)
stale=[]
for path,v in o.items():
 t=ROOT/path;want=c.pretty(v)
 if a.apply:t.parent.mkdir(parents=True,exist_ok=True);t.write_bytes(want)
 elif not t.is_file() or t.read_bytes()!=want:stale.append(path)
if stale:print('C45 generator check FAIL_STATIC_STALE '+','.join(stale));raise SystemExit(1)
print(f"C45 generator {'apply' if a.apply else 'check'} PASS_STATIC_PROVISIONAL generated={len(o)}")

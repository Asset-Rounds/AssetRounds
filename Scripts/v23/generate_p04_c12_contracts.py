#!/usr/bin/env python3
"""Render/check provisional C12 evidence artifacts."""
import argparse,json,os,sys
os.environ["PYTHONDONTWRITEBYTECODE"]="1"
from p04_c12_contracts import ROOT,documents,pretty
p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true");p.add_argument("--check",action="store_true");a=p.parse_args()
if a.apply==a.check:p.error("choose exactly one of --apply or --check")
try:
 out={k:pretty(v) for k,v in documents().items()};stale=[k for k,v in out.items() if not (ROOT/k).is_file() or (ROOT/k).read_bytes()!=v]
 if a.check:
  if stale:raise ValueError("artifact drift:"+",".join(stale))
  print("C12 generator check PASS_STATIC_PROVISIONAL")
 else:
  for k,v in out.items():(ROOT/k).parent.mkdir(parents=True,exist_ok=True);(ROOT/k).write_bytes(v)
  print("C12 generator apply PASS_STATIC_PROVISIONAL generated="+str(len(out)))
except Exception as e:print("C12 generator FAIL_STATIC:"+str(e),file=sys.stderr);raise SystemExit(1)

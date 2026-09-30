from __future__ import annotations
import argparse,json
from pathlib import Path
from p06_c08_contracts import ROOT,docs,pretty
def main():
 a=argparse.ArgumentParser(); a.add_argument('--apply',action='store_true'); a.add_argument('--check',action='store_true'); a.add_argument('--self-test',action='store_true'); q=a.parse_args()
 if q.self_test: assert docs()[next(iter(docs()))]; print('PASS_SELF_TEST'); return
 if q.apply==q.check: a.error('choose exactly one of --apply or --check')
 generated=docs(); drift=[]
 for rel,value in generated.items():
  path=ROOT/rel; data=pretty(value)
  if q.apply: path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data)
  elif not path.is_file() or path.read_bytes()!=data: drift.append(rel)
 if drift: raise SystemExit('DRIFT: '+','.join(drift))
 print('PASS_STATIC_PROVISIONAL')
if __name__=='__main__': main()

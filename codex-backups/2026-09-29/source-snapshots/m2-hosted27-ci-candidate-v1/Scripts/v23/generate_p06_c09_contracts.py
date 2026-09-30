from __future__ import annotations
import argparse
from p06_c09_contracts import ROOT,docs,pretty
def main():
 a=argparse.ArgumentParser();a.add_argument('--apply',action='store_true');a.add_argument('--check',action='store_true');a.add_argument('--self-test',action='store_true');q=a.parse_args()
 if q.self_test:assert docs();print('PASS_SELF_TEST');return
 if q.apply==q.check:a.error('choose exactly one of --apply or --check')
 drift=[]
 for rel,v in docs().items():
  p=ROOT/rel;b=pretty(v)
  if q.apply:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
  elif not p.is_file()or p.read_bytes()!=b:drift.append(rel)
 if drift:raise SystemExit('DRIFT: '+','.join(drift))
 print('PASS_STATIC_PROVISIONAL')
if __name__=='__main__':main()

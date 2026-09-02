import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent)); import p06_c02_contracts as c
p=argparse.ArgumentParser();p.add_argument('--apply',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--self-test',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args()
if a.self_test:
 r=c.self_test();print(json.dumps(r,sort_keys=True) if a.json else r['result']);raise SystemExit(0)
if a.apply==a.check:p.error('choose exactly one of --apply or --check')
try:
 docs={k:c.pretty(v) for k,v in c.documents().items()};drift=[k for k,v in docs.items() if not(c.ROOT/k).is_file() or(c.ROOT/k).read_bytes()!=v]
 if a.check:
  if drift:raise ValueError('artifact drift:'+','.join(drift))
  print('P06-C02 generator check PASS_STATIC_PROVISIONAL')
 else:
  for k,v in docs.items():
   target=c.ROOT/k;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(v)
  print('P06-C02 generator apply PASS_STATIC_PROVISIONAL generated='+str(len(docs)))
except Exception as e:print('P06-C02 generator FAIL_STATIC:'+str(e),file=sys.stderr);raise SystemExit(1)

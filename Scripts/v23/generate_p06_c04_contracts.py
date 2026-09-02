import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p06_c04_contracts as c
p=argparse.ArgumentParser();p.add_argument('--apply',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--self-test',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args()
if a.self_test:r=c.self_test();print(json.dumps(r,sort_keys=True)if a.json else r['result']);raise SystemExit(0)
if a.apply==a.check:p.error('choose one')
try:
 d={k:c.pretty(v)for k,v in c.docs().items()};bad=[k for k,v in d.items()if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=v]
 if a.check:
  if bad:raise ValueError('artifact drift:'+','.join(bad))
  print('P06-C04 generator check PASS_STATIC_PROVISIONAL')
 else:
  for k,v in d.items():t=c.ROOT/k;t.parent.mkdir(parents=True,exist_ok=True);t.write_bytes(v)
  print('P06-C04 generator apply PASS_STATIC_PROVISIONAL generated='+str(len(d)))
except Exception as e:print('P06-C04 generator FAIL_STATIC:'+str(e),file=sys.stderr);raise SystemExit(1)

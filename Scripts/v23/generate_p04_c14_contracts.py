import argparse,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c14_contracts as c
p=argparse.ArgumentParser();p.add_argument('--apply',action='store_true');p.add_argument('--check',action='store_true');a=p.parse_args()
if a.apply==a.check:p.error('choose exactly one')
try:
 o={k:c.pretty(v)for k,v in c.documents().items()};stale=[k for k,v in o.items()if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=v]
 if a.check:
  if stale:raise ValueError('artifact drift:'+','.join(stale))
  print('C14 generator check PASS_STATIC_PROVISIONAL')
 else:
  for k,v in o.items():(c.ROOT/k).parent.mkdir(parents=True,exist_ok=True);(c.ROOT/k).write_bytes(v)
  print('C14 generator apply PASS_STATIC_PROVISIONAL generated=4')
except Exception as e:print('C14 generator FAIL_STATIC:'+str(e),file=sys.stderr);raise SystemExit(1)

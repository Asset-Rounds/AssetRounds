import argparse,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p06_c07_contracts as c
p=argparse.ArgumentParser();p.add_argument('--apply',action='store_true');p.add_argument('--check',action='store_true');a=p.parse_args()
if p.parse_args().apply==p.parse_args().check:p.error('choose one')
d={k:c.pretty(v)for k,v in c.docs().items()};bad=[k for k,v in d.items()if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=v]
if p.parse_args().check:
 if bad:raise SystemExit('drift:'+','.join(bad))
 print('P06-C07 generator check PASS_STATIC_PROVISIONAL')
else:
 for k,v in d.items():t=c.ROOT/k;t.parent.mkdir(parents=True,exist_ok=True);t.write_bytes(v)
 print('P06-C07 generator apply PASS_STATIC_PROVISIONAL')

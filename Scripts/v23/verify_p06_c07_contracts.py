import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p06_c07_contracts as c
p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();f=[]
try:
 c.verify();q=json.loads((c.ROOT/c.CP).read_bytes())
 if q!=c.corpus():raise ValueError('corpus')
 for k,v in c.docs().items():
  if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=c.pretty(v):f.append('drift:'+k)
 n=c.counts()
 if n['changedPathCount']!=9 or n['missingOwnedPathCount']or n['unownedChangedPathCount']:f.append('fence')
except Exception as e:f.append(str(e));n={}
r={'cardID':c.CARD,'result':'FAIL_STATIC'if f else'PASS_STATIC_PROVISIONAL','failures':f,'counts':n};print(json.dumps(r,indent=2)if a.json else r['result']);raise SystemExit(bool(f))

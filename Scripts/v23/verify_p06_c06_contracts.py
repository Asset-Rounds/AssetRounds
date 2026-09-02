import argparse,ast,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p06_c06_contracts as c
p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();f=[]
try:
 c.verify();c.validate(c.protocol());c.self_test();q=c.load(c.CP)
 if q!=c.corpus()or tuple(x['id']for x in q['cases'])!=c.IDS:raise ValueError('corpus')
 h={x['id']:x.get('expected')for x in q['cases']if x['kind']=='hostile'}
 if h!={c.IDS[2]:'REJECT_DAMAGED',c.IDS[3]:'REJECT_DUPLICATE',c.IDS[4]:'REJECT_FOREIGN',c.IDS[5]:'REJECT_REVOKED',c.IDS[6]:'REJECT_REPLACED'}:raise ValueError('hostile')
 for k,v in {k:c.pretty(v)for k,v in c.docs().items()}.items():
  if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=v:f.append('drift:'+k)
 for k in c.S:ast.parse((c.ROOT/k).read_text())
 n=c.counts()
 if n['changedPathCount']!=9 or n['missingOwnedPathCount']or n['unownedChangedPathCount']or n['s10ReservationOverlapCount']:f.append('fence')
except Exception as e:f.append('contracts:'+str(e));n=c.counts()if 'c'in globals()else{}
r={'cardID':c.CARD,'result':'FAIL_STATIC'if f else'PASS_STATIC_PROVISIONAL','disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','failures':f,'counts':n,'authority':c.authority(),'flags':c.FLAGS};print(json.dumps(r,sort_keys=True,indent=2)if a.json else r['result']);raise SystemExit(bool(f))

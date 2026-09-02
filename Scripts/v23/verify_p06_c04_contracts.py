import argparse,ast,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p06_c04_contracts as c
p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();f=[]
try:
 c.verify();c.validate(c.protocol());c.self_test();q=c.load(c.CP)
 if q!=c.corpus()or tuple(x['id']for x in q['cases'])!=c.IDS:raise ValueError('corpus')
 h={x['id']:(x['input'],x['expected'])for x in q['cases']if x['kind']=='hostile'}
 if h!={c.IDS[2]:('malformed threshold descriptor','REJECT_NO_STUDY'),c.IDS[3]:('meter device BLE camera or network request','REJECT_DEVICE_INVOCATION'),c.IDS[4]:('license compliance accuracy or attestation claim','REJECT_CLAIM')}:raise ValueError('hostile')
 for k,v in {k:c.pretty(v)for k,v in c.docs().items()}.items():
  if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=v:f.append('artifact-drift:'+k)
 for k in c.S:ast.parse((c.ROOT/k).read_text())
 n=c.counts()
 if n['changedPathCount']!=9 or n['missingOwnedPathCount']or n['unownedChangedPathCount']or n['s10ReservationOverlapCount']:f.append('path-fence')
except Exception as e:f.append('contracts:'+str(e));n=c.counts()if 'c'in globals()else{}
r={'cardID':c.CARD,'result':'FAIL_STATIC'if f else'PASS_STATIC_PROVISIONAL','disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','completeRequested':a.complete,'failures':f,'counts':n,'authority':c.authority(),'observedCandidate':{'head':c.git('rev-parse','HEAD'),'tree':c.git('rev-parse','HEAD^{tree}'),'baseHead':c.BASE,'baseTree':c.TREE},'flags':c.FLAGS,'noRealStudy':True,'noProductionPath':True};print(json.dumps(r,sort_keys=True,indent=2)if a.json else r['result']);raise SystemExit(bool(f))

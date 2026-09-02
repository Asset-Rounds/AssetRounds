import argparse,ast,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p06_c03_contracts as c
p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();f=[]
try:
 c.verify();c.validate(c.protocol());c.self_test();q=c.load(c.CORPUS)
 if q!=c.corpus()or tuple(x['id']for x in q['cases'])!=c.IDS:raise ValueError('corpus differs')
 h={x['id']:(x['input'],x['expected'])for x in q['cases']if x['kind']=='hostile'}
 if h!={c.IDS[2]:('malformed field type','REJECT_NO_STUDY'),c.IDS[3]:('EAV or new writer/store/renderer request','REJECT_OUT_OF_SCOPE'),c.IDS[4]:('import export backend network customer payload or public claim','REJECT_OUT_OF_SCOPE')}:raise ValueError('hostile disposition differs')
 for k,v in {k:c.pretty(v)for k,v in c.docs().items()}.items():
  if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=v:f.append('artifact-drift:'+k)
 for k in c.SCRIPTS:ast.parse((c.ROOT/k).read_text(encoding='utf8'))
 n=c.counts()
 if n['changedPathCount']!=9 or n['missingOwnedPathCount']or n['unownedChangedPathCount']or n['s10ReservationOverlapCount']:f.append('path-fence')
except Exception as e:f.append('contracts:'+str(e));n=c.counts()if 'c'in globals()else{}
r={'cardID':c.CARD,'result':'FAIL_STATIC'if f else'PASS_STATIC_PROVISIONAL','disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','completeRequested':a.complete,'failures':f,'counts':n,'authority':c.authority(),'observedCandidate':{'head':c.git('rev-parse','HEAD'),'tree':c.git('rev-parse','HEAD^{tree}'),'baseHead':c.BASE,'baseTree':c.TREE},'flags':c.FLAGS,'noRealStudy':True,'noProductionPath':True};print(json.dumps(r,sort_keys=True,indent=2)if a.json else r['result']);raise SystemExit(bool(f))

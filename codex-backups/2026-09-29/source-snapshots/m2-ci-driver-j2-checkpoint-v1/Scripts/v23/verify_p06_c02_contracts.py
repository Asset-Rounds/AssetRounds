import argparse,ast,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p06_c02_contracts as c
p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();fail=[]
try:
 c.verify_identities();c.validate_protocol(c.protocol());c.self_test();corpus=c.load(c.CORPUS)
 if corpus!=c.corpus() or tuple(x['id'] for x in corpus['cases'])!=c.CASE_IDS:raise ValueError('corpus semantics differ')
 hostile={x['id']:(x['input'],x['expected']) for x in corpus['cases'] if x['kind']=='hostile'}
 if hostile!={c.CASE_IDS[2]:('malformed capability descriptor','REJECT_NO_STUDY'),c.CASE_IDS[3]:('network invocation request','REJECT_OUT_OF_SCOPE'),c.CASE_IDS[4]:('captured media model output or location data','REJECT_NO_DATA_CAPTURE')}:raise ValueError('hostile disposition differs')
 for k,v in {k:c.pretty(v) for k,v in c.documents().items()}.items():
  if not(c.ROOT/k).is_file() or(c.ROOT/k).read_bytes()!=v:fail.append('artifact-drift:'+k)
 for k in c.SCRIPTS:ast.parse((c.ROOT/k).read_text(encoding='utf8'))
 n=c.counts()
 if n['changedPathCount']!=len(c.OWNED) or n['missingOwnedPathCount'] or n['unownedChangedPathCount'] or n['s10ReservationOverlapCount']:fail.append('path-fence')
except Exception as e:fail.append('contracts:'+str(e));n=c.counts() if 'c' in globals() else {}
r={'cardID':c.CARD,'result':'FAIL_STATIC' if fail else 'PASS_STATIC_PROVISIONAL','disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','completeRequested':a.complete,'failures':fail,'counts':n,'authority':c.authority(),'observedCandidate':c.observed_candidate(),'flags':c.FLAGS,'noRealStudy':True,'noProductionPath':True};print(json.dumps(r,sort_keys=True,indent=2)if a.json else r['result']);raise SystemExit(bool(fail))

from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent)); import p05_c01_contracts as c
def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--complete',action='store_true'); parser.add_argument('--json',action='store_true'); args=parser.parse_args(); failures=[]; ready=False; counts={}
    try:
        c.require_authority(c.authority()); ready=c.source_ready(); c.semantics(ready); counts=c.counts(); docs=c.documents()
        for path,value in docs.items():
            if not (c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=c.pretty(value): failures.append('artifact-drift:'+path)
        if counts.get('unownedChangedPathCount') or counts.get('s10ReservationOverlapCount'): failures.append('fence:unowned-or-S10')
        if args.complete and not ready: failures.append('complete:source-lanes-pending')
        if any(v for k,v in c.FLAGS.items() if k!='requiresAcceptedS10_6') or c.FLAGS['requiresAcceptedS10_6'] is not True: failures.append('provisional:flags')
    except Exception as error: failures.append('contracts:'+str(error))
    result={'cardID':c.CARD,'attemptID':1,'result':'FAIL_STATIC' if failures else 'PASS_STATIC_PROVISIONAL','sourceReady':ready,'finalHashesSealed':False,'flagsAllFalse':not any(v for k,v in c.FLAGS.items() if k!='requiresAcceptedS10_6'),'requiresAcceptedS10_6':True,'failures':failures,'counts':counts,'fencePathCount':14,'existingPathCount':2,'newPathCount':12,'selectorRows':[{'id':x[0],'memberCount':x[1],'digest':x[2]} for x in c.SELECTOR_ROWS]}
    print(json.dumps(result,sort_keys=True,indent=2) if args.json else result['result']); raise SystemExit(bool(failures))
if __name__=='__main__': main()

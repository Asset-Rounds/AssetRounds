from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent)); import p04_c29_contracts as c
def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--complete',action='store_true'); parser.add_argument('--json',action='store_true'); args=parser.parse_args(); failures=[]; ready=False; counts={}; observed={}
    try:
        c.authority(); _,ready=c.rows(); c.semantics(ready); counts=c.counts(); observed=c.observation(); docs=c.documents()
        for path,value in docs.items():
            if not(c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=c.pretty(value): failures.append('artifact-drift:'+path)
        if counts.get('unownedChangedPathCount') or counts.get('s10ReservationOverlapCount'): failures.append('fence:unowned-or-S10')
        if args.complete and not ready: failures.append('complete:source-lanes-pending')
        if c.FINAL_HASHES_SEALED is not False or not all(value is False for value in c.FLAGS.values()): failures.append('provisional:flags')
    except Exception as error: failures.append('contracts:'+str(error))
    result={'cardID':c.CARD,'attemptID':2,'result':'FAIL_STATIC' if failures else 'PASS_STATIC_PROVISIONAL','sourceReady':ready,'finalHashesSealed':c.FINAL_HASHES_SEALED,'flagsAllFalse':all(value is False for value in c.FLAGS.values()),'failures':failures,'counts':counts,'fencePathCount':14,'existingPathCount':2,'newPathCount':12,'selectors':list(c.SELECTORS),'observedSelfTest':observed}
    print(json.dumps(result,sort_keys=True,indent=2) if args.json else result['result']); raise SystemExit(bool(failures))
if __name__=='__main__':main()

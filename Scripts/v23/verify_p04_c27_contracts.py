from __future__ import annotations
import argparse, json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import p04_c27_contracts as c
def main():
    p=argparse.ArgumentParser(); p.add_argument('--complete',action='store_true'); p.add_argument('--json',action='store_true'); a=p.parse_args(); failures=[]; ready=False; counts={}
    try:
        c.authority(); rows,ready=c.rows(); c.semantics(ready); counts=c.counts(); docs=c.documents()
        for path,value in docs.items():
            if not (c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=c.pretty(value): failures.append('artifact-drift:'+path)
        if counts['unownedChangedPathCount'] or counts['s10ReservationOverlapCount']: failures.append('fence:unowned-or-S10')
        if a.complete and not ready: failures.append('complete:source-lanes-pending')
        if c.FINAL_HASHES_SEALED is not False: failures.append('provisional:final-hashes-must-remain-unsealed')
    except Exception as error: failures.append('contracts:'+str(error))
    value={'cardID':c.CARD,'result':'FAIL_STATIC' if failures else 'PASS_STATIC_PROVISIONAL','sourceReady':ready,'finalHashesSealed':c.FINAL_HASHES_SEALED,'flagsAllFalse':all(flag is False for flag in c.FLAGS.values()),'failures':failures,'counts':counts,'fencePathCount':14,'existingPathCount':2,'newPathCount':12,'selectors':list(c.SELECTORS)}
    print(json.dumps(value,sort_keys=True,indent=2) if a.json else value['result']); raise SystemExit(bool(failures))
if __name__=='__main__': main()

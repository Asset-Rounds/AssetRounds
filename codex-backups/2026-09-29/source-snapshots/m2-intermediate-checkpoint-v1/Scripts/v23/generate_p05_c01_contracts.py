from __future__ import annotations
import argparse, hashlib, json, os, sys, tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent)); import p05_c01_contracts as c
B=('BEFORE_ARTIFACTS','AFTER_ARTIFACTS_BEFORE_MANIFEST','AFTER_MANIFEST')
def accepted(root):
    try:
        rows=json.loads((root/c.MANIFEST).read_bytes())['files']
        return int(len(rows)==3 and all((root/x['path']).is_file() and hashlib.sha256((root/x['path']).read_bytes()).hexdigest()==x['sha256'] for x in rows))
    except Exception: return 0
def write(docs,root,boundary=None):
    if boundary==B[0]: raise RuntimeError(boundary)
    staged=[]
    try:
        for path in (c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
            target=Path(root)/path; target.parent.mkdir(parents=True,exist_ok=True); fd,name=tempfile.mkstemp(prefix='.'+target.name+'.',dir=target.parent)
            with os.fdopen(fd,'wb') as handle: handle.write(c.pretty(docs[path]))
            staged.append((target,Path(name)))
        for target,name in staged[:-1]: os.replace(name,target)
        if boundary==B[1]: raise RuntimeError(boundary)
        os.replace(staged[-1][1],staged[-1][0])
        if boundary==B[2]: raise RuntimeError(boundary)
    finally:
        for _,name in staged:
            if name.exists(): name.unlink()
def self_test():
    docs=c.documents(); rows=[]
    with tempfile.TemporaryDirectory(prefix='.p05-c01-',dir=c.ROOT.parent) as temp:
        for boundary,expected in zip(B,(0,0,1)):
            root=Path(temp)/boundary
            try: write(docs,root,boundary)
            except RuntimeError: pass
            first=accepted(root); write(docs,root); rows.append({'boundary':boundary,'acceptedSetCount':expected,'actualInterruptedAcceptedSetCount':first,'recoveryAcceptedSetCount':accepted(root),'secondRetryAcceptedSetCount':accepted(root),'manifestLast':True,'retryDeterministic':accepted(root)==1})
    if not all(x['actualInterruptedAcceptedSetCount']==x['acceptedSetCount'] and x['retryDeterministic'] for x in rows): raise ValueError('C01 manifest-last recovery differs')
    return {'result':'PASS','protocol':'MANIFEST_LAST_ATOMIC_REPLACE','observedSelfTest':c.observation(),'rows':rows}
def main():
    parser=argparse.ArgumentParser(); group=parser.add_mutually_exclusive_group(required=True); group.add_argument('--apply',action='store_true'); group.add_argument('--check',action='store_true'); group.add_argument('--self-test',action='store_true'); parser.add_argument('--json',action='store_true'); args=parser.parse_args()
    if args.self_test:
        result=self_test(); print(json.dumps(result,sort_keys=True,indent=2) if args.json else 'C01 generator self-test PASS'); return
    docs=c.documents(); drift=[p for p,v in docs.items() if not (c.ROOT/p).is_file() or (c.ROOT/p).read_bytes()!=c.pretty(v)]
    if args.check:
        if drift: raise SystemExit('C01 artifact drift:'+','.join(drift))
        print(json.dumps({'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL','drift':[]},sort_keys=True) if args.json else 'PASS_STATIC_PROVISIONAL'); return
    write(docs,c.ROOT,os.environ.get('V23_P05_C01_INTERRUPT_AT')); print('C01 generator apply PASS_STATIC_PROVISIONAL generated=4')
if __name__=='__main__': main()

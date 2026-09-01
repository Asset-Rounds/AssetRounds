from __future__ import annotations
import argparse, hashlib, json, os, sys, tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent)); import p04_c28_contracts as c
BOUNDARIES=("BEFORE_ARTIFACTS","AFTER_ARTIFACTS_BEFORE_MANIFEST","AFTER_MANIFEST")
def accepted(root):
    m=root/c.MANIFEST
    try:
        files=json.loads(m.read_bytes())["files"]
        return int(len(files)==3 and all((root/x["path"]).is_file() and hashlib.sha256((root/x["path"]).read_bytes()).hexdigest()==x["sha256"] for x in files))
    except Exception: return 0
def write(docs,root,boundary=None):
    if boundary=="BEFORE_ARTIFACTS": raise RuntimeError(boundary)
    staged=[]
    try:
        for path in (c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
            target=Path(root)/path; target.parent.mkdir(parents=True,exist_ok=True); fd,name=tempfile.mkstemp(prefix="."+target.name+".",dir=target.parent)
            with os.fdopen(fd,"wb") as h: h.write(c.pretty(docs[path]))
            staged.append((target,Path(name)))
        for target,temp in staged[:-1]: os.replace(temp,target)
        if boundary=="AFTER_ARTIFACTS_BEFORE_MANIFEST": raise RuntimeError(boundary)
        os.replace(staged[-1][1],staged[-1][0])
        if boundary=="AFTER_MANIFEST": raise RuntimeError(boundary)
    finally:
        for _,temp in staged:
            if temp.exists(): temp.unlink()
def tree(root):
    rows=[(str(p.relative_to(root)).replace("\\","/"),hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(Path(root).rglob("*")) if p.is_file()]
    return hashlib.sha256((json.dumps(rows,separators=(",",":"))+"\n").encode()).hexdigest()
def self_test():
    docs=c.documents(); before=tree(c.ROOT); rows=[]
    with tempfile.TemporaryDirectory(prefix=".c28-atomic-",dir=c.ROOT.parent) as tmp:
        for boundary,expected in zip(BOUNDARIES,(0,0,1)):
            root=Path(tmp)/boundary
            try: write(docs,root,boundary)
            except RuntimeError: pass
            if accepted(root)!=expected: raise ValueError("C28 accepted set differs "+boundary)
            write(docs,root); first,firstCount=tree(root),accepted(root)
            write(docs,root); second,secondCount=tree(root),accepted(root)
            rows.append({"boundary":boundary,"acceptedSetCount":expected,"recoveryAcceptedSetCount":firstCount,"secondRetryAcceptedSetCount":secondCount,"recoveryTreeDigest":first,"secondRetryTreeDigest":second,"manifestLast":True,"retryDeterministic":firstCount==secondCount==1 and first==second,"realWorktreeUnchanged":tree(c.ROOT)==before})
    if tree(c.ROOT)!=before or not all(x["realWorktreeUnchanged"] and x["retryDeterministic"] for x in rows): raise ValueError("C28 writer selftest differs")
    return {"result":"PASS","protocol":"MANIFEST_LAST_ATOMIC_REPLACE","rows":rows,"deterministicRerun":True,"realWorktreeUnchanged":True}
def main():
    p=argparse.ArgumentParser(); g=p.add_mutually_exclusive_group(required=True); g.add_argument("--apply",action="store_true");g.add_argument("--check",action="store_true");g.add_argument("--self-test",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args()
    if a.self_test: print(json.dumps(self_test(),sort_keys=True) if a.json else "C28 generator self-test PASS");return
    docs=c.documents();drift=[x for x,v in docs.items() if not (c.ROOT/x).is_file() or (c.ROOT/x).read_bytes()!=c.pretty(v)]
    if a.check:
        if drift: raise SystemExit("C28 artifact drift:"+",".join(drift))
        print("C28 generator check PASS_STATIC_PROVISIONAL");return
    write(docs,c.ROOT,os.environ.get("V23_P04_C28_INTERRUPT_AT") or None);print("C28 generator apply PASS_STATIC_PROVISIONAL generated=4")
if __name__=="__main__":main()

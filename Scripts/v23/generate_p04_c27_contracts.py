from __future__ import annotations
import argparse, hashlib, json, os, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c27_contracts as c

BOUNDARIES = ('BEFORE_ARTIFACTS', 'AFTER_ARTIFACTS_BEFORE_MANIFEST', 'AFTER_MANIFEST')
def accepted(root):
    manifest = root / c.MANIFEST
    if not manifest.is_file(): return 0
    try:
        files = {row['path']: row['sha256'] for row in json.loads(manifest.read_bytes())['files']}
        return int(len(files) == 3 and all((root / path).is_file() and hashlib.sha256((root / path).read_bytes()).hexdigest() == digest for path, digest in files.items()))
    except (KeyError, TypeError, ValueError, json.JSONDecodeError): return 0
def write(docs, root, boundary=None):
    if boundary == 'BEFORE_ARTIFACTS': raise RuntimeError(boundary)
    staged=[]
    try:
        for path in (c.CONTRACT, c.EVIDENCE, c.BRAND, c.MANIFEST):
            target=Path(root)/path; target.parent.mkdir(parents=True, exist_ok=True); fd,name=tempfile.mkstemp(prefix='.'+target.name+'.',dir=target.parent)
            with os.fdopen(fd,'wb') as handle: handle.write(c.pretty(docs[path]))
            staged.append((target,Path(name)))
        for target,temp in staged[:-1]: os.replace(temp,target)
        if boundary == 'AFTER_ARTIFACTS_BEFORE_MANIFEST': raise RuntimeError(boundary)
        os.replace(staged[-1][1],staged[-1][0])
        if boundary == 'AFTER_MANIFEST': raise RuntimeError(boundary)
    finally:
        for _,temp in staged:
            if temp.exists(): temp.unlink()
def digest_tree(root):
    rows=[(str(path.relative_to(root)).replace('\\','/'),hashlib.sha256(path.read_bytes()).hexdigest()) for path in sorted(Path(root).rglob('*')) if path.is_file()]
    return hashlib.sha256((json.dumps(rows,separators=(',',':'))+'\n').encode()).hexdigest()
def self_test():
    docs=c.documents(); baseline=digest_tree(c.ROOT); rows=[]
    with tempfile.TemporaryDirectory(prefix='.c27-atomic-',dir=c.ROOT.parent) as box:
        for boundary,expected in zip(BOUNDARIES,(0,0,1)):
            root=Path(box)/boundary
            try: write(docs,root,boundary)
            except RuntimeError: pass
            if accepted(root)!=expected: raise ValueError('C27 interruption acceptance differs:'+boundary)
            write(docs,root)
            recovered_digest, recovered_count = digest_tree(root), accepted(root)
            write(docs,root)
            retry_digest, retry_count = digest_tree(root), accepted(root)
            rows.append({'boundary':boundary,'acceptedSetCount':expected,'manifestLast':True,'temporaryRootMayContainIncompleteArtifacts':boundary!='AFTER_MANIFEST','recoveryAcceptedSetCount':recovered_count,'recoveryTreeDigest':recovered_digest,'secondRetryAcceptedSetCount':retry_count,'secondRetryTreeDigest':retry_digest,'retryAcceptedSetCount':retry_count,'retryDeterministic':recovered_count==1 and retry_count==1 and recovered_digest==retry_digest,'realWorktreeUnchanged':digest_tree(c.ROOT)==baseline})
    if digest_tree(c.ROOT)!=baseline or not all(x['realWorktreeUnchanged'] for x in rows): raise ValueError('C27 self-test mutated worktree')
    return {'result':'PASS','protocol':'MANIFEST_LAST_ATOMIC_REPLACE','rows':rows,'deterministicRerun':all(row['retryDeterministic'] for row in rows),'realWorktreeUnchanged':True}
def main():
    p=argparse.ArgumentParser(); g=p.add_mutually_exclusive_group(required=True); g.add_argument('--apply',action='store_true'); g.add_argument('--check',action='store_true'); g.add_argument('--self-test',action='store_true'); p.add_argument('--json',action='store_true'); a=p.parse_args()
    if a.self_test: print(json.dumps(self_test(),sort_keys=True) if a.json else 'C27 generator self-test PASS'); return
    docs=c.documents(); drift=[path for path,value in docs.items() if not (c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=c.pretty(value)]
    if a.check:
        if drift: raise SystemExit('C27 artifact drift:'+','.join(drift))
        print('C27 generator check PASS_STATIC_PROVISIONAL'); return
    write(docs,c.ROOT,os.environ.get('V23_P04_C27_INTERRUPT_AT') or None); print('C27 generator apply PASS_STATIC_PROVISIONAL generated=4')
if __name__=='__main__': main()

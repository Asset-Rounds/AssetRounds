from __future__ import annotations
import argparse,hashlib,json,os,sys,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c29_contracts as c
B=('BEFORE_ARTIFACTS','AFTER_ARTIFACTS_BEFORE_MANIFEST','AFTER_MANIFEST')
def accepted(root):
 try:
  rows=json.loads((root/c.MANIFEST).read_bytes())['files'];return int(len(rows)==3 and all((root/x['path']).is_file() and hashlib.sha256((root/x['path']).read_bytes()).hexdigest()==x['sha256'] for x in rows))
 except Exception:return 0
def write(docs,root,boundary=None):
 if boundary==B[0]:raise RuntimeError(boundary)
 staged=[]
 try:
  for p in (c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
   t=Path(root)/p;t.parent.mkdir(parents=True,exist_ok=True);fd,n=tempfile.mkstemp(prefix='.'+t.name+'.',dir=t.parent)
   with os.fdopen(fd,'wb') as h:h.write(c.pretty(docs[p]))
   staged.append((t,Path(n)))
  for t,n in staged[:-1]:os.replace(n,t)
  if boundary==B[1]:raise RuntimeError(boundary)
  os.replace(staged[-1][1],staged[-1][0])
  if boundary==B[2]:raise RuntimeError(boundary)
 finally:
  for _,n in staged:
   if n.exists():n.unlink()
def digest(root):
 rows=[(str(p.relative_to(root)).replace('\\','/'),hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(Path(root).rglob('*')) if p.is_file()];return hashlib.sha256((json.dumps(rows,separators=(',',':'))+'\n').encode()).hexdigest()
def self_test():
 docs=c.documents();before=digest(c.ROOT);rows=[]
 with tempfile.TemporaryDirectory(prefix='.c29-atomic-',dir=c.ROOT.parent) as d:
  for b,expect in zip(B,(0,0,1)):
   r=Path(d)/b
   try:write(docs,r,b)
   except RuntimeError:pass
   if accepted(r)!=expect:raise ValueError('C29 acceptance differs '+b)
   write(docs,r);one,n1=digest(r),accepted(r);write(docs,r);two,n2=digest(r),accepted(r);rows.append({'boundary':b,'acceptedSetCount':expect,'recoveryAcceptedSetCount':n1,'secondRetryAcceptedSetCount':n2,'recoveryTreeDigest':one,'secondRetryTreeDigest':two,'manifestLast':True,'retryDeterministic':n1==n2==1 and one==two,'realWorktreeUnchanged':digest(c.ROOT)==before})
 if digest(c.ROOT)!=before or not all(x['retryDeterministic'] and x['realWorktreeUnchanged'] for x in rows):raise ValueError('C29 selftest differs')
 return {'result':'PASS','protocol':'MANIFEST_LAST_ATOMIC_REPLACE','rows':rows,'deterministicRerun':True,'realWorktreeUnchanged':True}
def main():
 p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True);g.add_argument('--apply',action='store_true');g.add_argument('--check',action='store_true');g.add_argument('--self-test',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args()
 if a.self_test:print(json.dumps(self_test(),sort_keys=True) if a.json else 'C29 generator self-test PASS');return
 docs=c.documents();drift=[p for p,v in docs.items() if not(c.ROOT/p).is_file() or(c.ROOT/p).read_bytes()!=c.pretty(v)]
 if a.check:
  if drift:raise SystemExit('C29 artifact drift:'+','.join(drift))
  print('C29 generator check PASS_STATIC_PROVISIONAL');return
 write(docs,c.ROOT,os.environ.get('V23_P04_C29_INTERRUPT_AT') or None);print('C29 generator apply PASS_STATIC_PROVISIONAL generated=4')
if __name__=='__main__':main()

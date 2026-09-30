from __future__ import annotations
import argparse,os,sys,tempfile
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c31_contracts as c
def write(docs):
 staged=[]
 try:
  for p in (c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
   q=c.ROOT/p;q.parent.mkdir(parents=True,exist_ok=True);f,n=tempfile.mkstemp(prefix="."+q.name+".",dir=q.parent)
   with os.fdopen(f,"wb")as h:h.write(c.pretty(docs[p]))
   staged.append((q,Path(n)))
  for q,n in staged[:-1]:os.replace(n,q)
  os.replace(staged[-1][1],staged[-1][0])
 finally:
  for _,n in staged:
   if n.exists():n.unlink()
def main():
 p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True);g.add_argument("--apply",action="store_true");g.add_argument("--check",action="store_true");a=p.parse_args();d=c.documents();drift=[x for x,v in d.items() if not(c.ROOT/x).is_file() or(c.ROOT/x).read_bytes()!=c.pretty(v)]
 if a.check:
  if drift:raise SystemExit("C31 artifact drift:"+",".join(drift))
  print("C31 generator check PASS_STATIC_PROVISIONAL");return
 write(d);print("C31 generator apply PASS_STATIC_PROVISIONAL generated=4")
if __name__=="__main__":main()

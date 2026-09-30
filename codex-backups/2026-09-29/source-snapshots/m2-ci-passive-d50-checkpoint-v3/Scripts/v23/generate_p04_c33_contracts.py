from __future__ import annotations
import argparse, os, sys, tempfile
from pathlib import Path
sys.dont_write_bytecode=True; sys.path.insert(0,str(Path(__file__).resolve().parent))
import p04_c33_contracts as c
def main():
 p=argparse.ArgumentParser(); g=p.add_mutually_exclusive_group(required=True); g.add_argument("--apply",action="store_true"); g.add_argument("--check",action="store_true"); a=p.parse_args(); d=c.documents(); drift=[x for x,v in d.items() if not (c.ROOT/x).is_file() or (c.ROOT/x).read_bytes()!=c.pretty(v)]
 if a.check:
  if drift: raise SystemExit("C33 artifact drift:"+",".join(drift))
  print("C33 generator check PASS_STATIC_PROVISIONAL"); return
 for x,v in d.items():
  q=c.ROOT/x; q.parent.mkdir(parents=True,exist_ok=True); fd,n=tempfile.mkstemp(prefix="."+q.name+".",dir=q.parent)
  with os.fdopen(fd,"wb") as f:f.write(c.pretty(v))
  os.replace(n,q)
 print("C33 generator apply PASS_STATIC_PROVISIONAL generated=5")
if __name__=="__main__":main()

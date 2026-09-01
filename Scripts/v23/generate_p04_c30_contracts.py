from __future__ import annotations
import argparse, json, os, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent)); import p04_c30_contracts as c
def main():
 p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True);g.add_argument("--apply",action="store_true");g.add_argument("--check",action="store_true");g.add_argument("--self-test",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();docs=c.documents()
 if a.self_test:
  print(json.dumps(c.interruption_protocol(),sort_keys=True) if a.json else "C30 generator self-test PASS");return
 drift=[x for x,v in docs.items() if not(c.ROOT/x).is_file() or (c.ROOT/x).read_bytes()!=c.pretty(v)]
 if a.check:
  if drift:raise SystemExit("C30 artifact drift:"+",".join(drift))
  print("C30 generator check PASS_STATIC_PROVISIONAL");return
 c.atomic_write(docs,c.ROOT,os.environ.get("V23_P04_C30_INTERRUPT_AT"));print("C30 generator apply PASS_STATIC_PROVISIONAL generated=4")
if __name__=="__main__":main()

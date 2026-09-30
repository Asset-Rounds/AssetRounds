from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c31_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();f=[];ready=False;counts={}
 try:
  c.authority();_,ready=c.rows();c.semantics(ready);counts=c.counts();d=c.documents()
  for x,v in d.items():
   if not(c.ROOT/x).is_file()or(c.ROOT/x).read_bytes()!=c.pretty(v):f.append("artifact-drift:"+x)
  if counts.get("unownedChangedPathCount") or counts.get("s10ReservationOverlapCount"):f.append("fence:unowned-or-S10")
  if a.complete and not ready:f.append("complete:source-lanes-pending")
 except Exception as e:f.append("contracts:"+str(e))
 o={"cardID":c.CARD,"result":"FAIL_STATIC" if f else "PASS_STATIC_PROVISIONAL","sourceReady":ready,"finalHashesSealed":False,"flagsAllFalse":all(x is False for x in c.FLAGS.values()),"failures":f,"counts":counts,"fencePathCount":17,"existingPathCount":4,"newPathCount":13,"selectors":list(c.SELECTORS)};print(json.dumps(o,sort_keys=True,indent=2)if a.json else o["result"]);raise SystemExit(bool(f))
if __name__=="__main__":main()

from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c28_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args(); failures=[];ready=False;counts={}
 try:
  c.authority();rows,ready=c.rows();c.semantics(ready);counts=c.counts();docs=c.documents()
  for path,v in docs.items():
   if not(c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=c.pretty(v):failures.append("artifact-drift:"+path)
  if counts.get("unownedChangedPathCount") or counts.get("s10ReservationOverlapCount"):failures.append("fence:unowned-or-S10")
  if a.complete and not ready:failures.append("complete:source-lanes-pending")
  if c.FINAL_HASHES_SEALED is not False:failures.append("provisional:must-remain-unsealed")
 except Exception as e:failures.append("contracts:"+str(e))
 out={"cardID":c.CARD,"result":"FAIL_STATIC" if failures else "PASS_STATIC_PROVISIONAL","sourceReady":ready,"finalHashesSealed":c.FINAL_HASHES_SEALED,"flagsAllFalse":all(x is False for x in c.FLAGS.values()),"failures":failures,"counts":counts,"fencePathCount":22,"existingPathCount":10,"newPathCount":12,"selectors":list(c.SELECTORS)}
 print(json.dumps(out,sort_keys=True,indent=2) if a.json else out["result"]);raise SystemExit(bool(failures))
if __name__=="__main__":main()

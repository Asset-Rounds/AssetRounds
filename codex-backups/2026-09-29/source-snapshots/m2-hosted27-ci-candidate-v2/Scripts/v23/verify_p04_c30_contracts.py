from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c30_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[];ready=False;counts={}
 try:
  c.authority();_,ready=c.rows();c.semantics(ready);counts=c.counts();docs=c.documents();fresh=c.interruption_protocol()
  if docs[c.EVIDENCE]["generatorInterruptionProtocol"] != fresh:fail.append("interruption:fresh-protocol-differs")
  for path,v in docs.items():
   if not(c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=c.pretty(v):fail.append("artifact-drift:"+path)
  if counts["unownedChangedPathCount"] or counts["s10ReservationOverlapCount"]:fail.append("fence:unowned-or-S10")
  if a.complete and not ready:fail.append("complete:source-lanes-pending")
 except Exception as e:fail.append("contracts:"+str(e))
 out={"cardID":c.CARD,"result":"FAIL_STATIC" if fail else "PASS_STATIC_PROVISIONAL","sourceReady":ready,"finalHashesSealed":c.FINAL_HASHES_SEALED,"flagsAllFalse":all(v is False for v in c.FLAGS.values()),"failures":fail,"counts":counts,"fencePathCount":13,"existingPathCount":2,"newPathCount":11,"selectors":list(c.SELECTORS)}
 print(json.dumps(out,sort_keys=True,indent=2) if a.json else out["result"]);raise SystemExit(bool(fail))
if __name__=="__main__":main()

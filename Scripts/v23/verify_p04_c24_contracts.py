import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c24_contracts as c
p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[];ready=False;n={}
try:
 c.authority();r,ready=c.rows();c.semantics(ready);n=c.counts();d={k:c.pretty(v)for k,v in c.documents().items()}
 for k,v in d.items():
  if not(c.ROOT/k).is_file()or(c.ROOT/k).read_bytes()!=v:fail.append("artifact-drift:"+k)
 if n["unownedChangedPathCount"]or n["s10ReservationOverlapCount"]:fail.append("fence:unowned/S10")
 if a.complete and(not ready or not c.FINAL_HASHES_SEALED):fail.append("complete:source lanes or owner-directed sealing pending")
except Exception as e:fail.append("contracts:"+str(e))
r={"cardID":c.CARD,"result":"FAIL_STATIC"if fail else"PASS_STATIC_PROVISIONAL","sourceReady":ready,"finalHashesSealed":c.FINAL_HASHES_SEALED,"failures":fail,"counts":n,"fencePathCount":40,"existingPathCount":26,"newPathCount":14,"selectors":list(c.SELECTORS),"flagsAllFalse":all(v is False for v in c.FLAGS.values())};print(json.dumps(r,sort_keys=True,indent=2)if a.json else r["result"]);raise SystemExit(bool(fail))

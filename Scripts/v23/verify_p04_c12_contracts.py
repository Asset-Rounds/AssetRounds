#!/usr/bin/env python3
"""Fail-closed verifier for C12 provisional tooling."""
import argparse,ast,json,os,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True;sys.path.insert(0,str(Path(__file__).resolve().parent))
import p04_c12_contracts as c
p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[];ready=False;counts={}
try:c.authority()
except Exception as e:fail.append("authority:"+str(e))
for path in c.SCRIPT_PATHS:
 try:ast.parse((c.ROOT/path).read_text(encoding="utf-8"),path)
 except Exception as e:fail.append("syntax:"+path+":"+str(e))
try:
 expected={k:c.pretty(v) for k,v in c.documents().items()}
 for k,v in expected.items():
  if not (c.ROOT/k).is_file() or (c.ROOT/k).read_bytes()!=v:fail.append("artifact-drift:"+k)
 rows,ready=c.source_rows();c.validate_source_semantics(rows,ready);counts=c.fence_rows()
 if counts["unownedChangedPathCount"]!=0 or counts["s10ReservationOverlapCount"]!=0:fail.append("fence:unowned/S10 path")
 if a.complete and not c.FINAL_HASHES_SEALED:fail.append("complete:FINAL_HASHES_SEALED=false")
except Exception as e:fail.append("contracts:"+str(e))
r={"cardID":c.CARD,"result":"FAIL_STATIC" if fail else "PASS_STATIC_PROVISIONAL","complete":a.complete,"finalHashesSealed":c.FINAL_HASHES_SEALED,"sourceReady":ready,"failures":fail,"fencePathCount":130,"existingPathCount":113,"newPathCount":17,"counts":counts,"selectors":list(c.SELECTORS),"flagsAllFalse":all(v is False for v in c.FLAGS.values())};print(json.dumps(r,sort_keys=True,indent=2) if a.json else r["result"]);raise SystemExit(bool(fail))

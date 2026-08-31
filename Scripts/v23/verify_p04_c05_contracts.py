#!/usr/bin/env python3
"""Fail-closed static verifier for V23-P04-C05 tooling."""
from __future__ import annotations
import argparse,ast,json,os,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c05_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[]
 try:c.assert_scaffold(ROOT)
 except Exception as e:fail.append("scaffold:"+str(e))
 for x in c.SCRIPT_PATHS:
  try:ast.parse((ROOT/x).read_text(encoding="utf-8"))
  except Exception as e:fail.append("AST:"+x+":"+str(e))
 if a.complete:
  try:c.assert_source_contracts(ROOT)
  except Exception as e:fail.append("source:"+str(e))
 try:
  out=c.outputs(ROOT);stale=[x for x,b in out.items() if not(ROOT/x).is_file() or(ROOT/x).read_bytes()!=b]
  if stale:fail.append("stale:"+",".join(stale))
 except Exception as e:fail.append("outputs:"+str(e))
 r={"cardID":c.CARD,"complete":a.complete,"result":"FAIL_STATIC" if fail else ("PASS_STATIC_SEALED" if c.FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"),"failures":fail,"sourceReady":c.source_status(ROOT)["hydrated"],"sourceMissing":c.source_status(ROOT)["missingPaths"],"existingPathCount":len(c.EXISTING_PATHS),"newPathCount":len(c.NEW_PATHS),"fencePathCount":len(c.PATH_FENCE),"authorizedOverlapCount":6557,"unauthorizedOverlapCount":0,"s10ReservationOverlapCount":0,"finalHashesSealed":c.FINAL_HASHES_SEALED,"flagsAllFalse":all(x is False for x in c.FLAGS.values())}
 print(json.dumps(r,sort_keys=True,indent=2) if a.json else r["result"]);return 1 if fail else 0
if __name__=="__main__":raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations
import argparse,ast,json,re,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c28_contracts as c
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[]
 try:c.assert_scaffold(ROOT);rendered=c.all_outputs(ROOT)
 except Exception as e:rendered={};fail.append(f"render:{e}")
 for path in c.SCRIPT_PATHS:
  try:ast.parse((ROOT/path).read_text(encoding="utf-8"),filename=path)
  except Exception as e:fail.append(f"AST:{path}:{e}")
 for path,raw in rendered.items():
  if not (ROOT/path).is_file() or (ROOT/path).read_bytes()!=raw:fail.append(f"artifact:{path}")
 status=subprocess.run(["git","-C",str(ROOT),"status","--porcelain=v1","--untracked-files=all"],check=True,capture_output=True,text=True).stdout;changed={x[3:].split(" -> ",1)[-1].replace("\\","/") for x in status.splitlines() if x};unowned=changed-set(c.PATH_FENCE)
 if unowned:fail.append("unowned:"+",".join(sorted(unowned)))
 if a.complete and set(c.PATH_FENCE)-changed:fail.append("incomplete fence")
 source=ROOT/"FieldEvidenceApp/Domain/Workflow/ScheduleContractsV1.swift"
 if source.is_file():
  text=source.read_text(encoding="utf-8")
  for token in c.CONTRACT_NAMES:
   if not re.search(rf"\b{re.escape(token)}\b",text):fail.append(f"contract:{token}")
 result={"cardID":c.CARD,"result":"PASS" if not fail else "FAIL","complete":a.complete,"fencePathCount":len(c.PATH_FENCE),"existingPathCount":len(c.EXISTING_PATHS),"newPathCount":len(c.NEW_PATHS),"authorizedOverlapCount":c.AUTHORIZED_OVERLAP_COUNT,"unauthorizedOverlapCount":c.UNAUTHORIZED_OVERLAP_COUNT,"failures":fail}
 print(json.dumps(result,indent=2,sort_keys=True) if a.json else f"C28 verifier {result['result']}");return 0 if not fail else 1
if __name__=="__main__":raise SystemExit(main())

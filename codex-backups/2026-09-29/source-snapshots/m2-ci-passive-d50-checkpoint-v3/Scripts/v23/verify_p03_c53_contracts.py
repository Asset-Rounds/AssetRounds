#!/usr/bin/env python3
from __future__ import annotations
import argparse,ast,json,os,subprocess,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c53_contracts as c
def _changed()->set[str]:
 run=lambda args:subprocess.run(args,cwd=ROOT,capture_output=True,text=True,check=True).stdout
 return set(run(["git","diff","--name-only",c.BASE_HEAD,"--"]).split())|set(run(["git","ls-files","--others","--exclude-standard"]).split())
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[];out={}
 try:
  c.assert_scaffold(ROOT)
  for path in c.SCRIPTS:ast.parse((ROOT/path).read_text(encoding="utf-8"),filename=path)
  out=c.all_outputs(ROOT)
 except Exception as error:fail.append(str(error))
 missing=[path for path in c.FENCE if not (ROOT/path).is_file()]
 if missing:fail.append("missing:"+",".join(missing))
 for path,value in out.items():
  if (ROOT/path).is_file() and (ROOT/path).read_bytes()!=value:fail.append("artifact differs:"+path)
 changed=_changed();fence_changed=changed&set(c.FENCE);unowned=changed-set(c.FENCE)
 if a.complete:
  if unowned:fail.append("unowned changed path:"+",".join(sorted(unowned)))
  incomplete=set(c.FENCE)-changed
  if incomplete:fail.append("incomplete fence:"+",".join(sorted(incomplete)))
 cache=list((ROOT/"Scripts/v23").rglob("*.pyc"))+list((ROOT/"Scripts/v23").rglob("__pycache__"))
 if cache:fail.append("python cache:"+",".join(str(x.relative_to(ROOT)) for x in cache))
 result={"cardID":c.CARD,"result":"PASS" if not fail else "FAIL","complete":a.complete,"existingPathCount":len(c.EXISTING),"newPathCount":len(c.NEW),"fencePathCount":len(c.FENCE),"changedPathCount":len(changed),"fenceChangedPathCount":len(fence_changed),"unownedChangedPathCount":len(unowned),"s10ReservationOverlapCount":0,"flagsAllFalse":not any(c.FLAGS.values()),"failures":fail}
 print(json.dumps(result,indent=2,sort_keys=True) if a.json else result["result"]);return 0 if not fail else 1
if __name__=="__main__":raise SystemExit(main())

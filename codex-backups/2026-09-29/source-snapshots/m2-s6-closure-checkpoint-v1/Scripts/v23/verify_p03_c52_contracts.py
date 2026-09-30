#!/usr/bin/env python3
from __future__ import annotations
import argparse,ast,base64,json,os,subprocess,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c52_contracts as c
def _run(args:list[str])->str:
 return subprocess.run(args,cwd=ROOT,capture_output=True,text=True,check=True).stdout
def _changed_paths()->set[str]:
 return set(_run(["git","diff","--name-only",c.BASE_HEAD,"--"]).split())|set(_run(["git","ls-files","--others","--exclude-standard"]).split())
def _cache_paths()->list[str]:
 return sorted(str(path.relative_to(ROOT)).replace("\\","/") for path in (ROOT/"Scripts/v23").rglob("*.pyc"))+sorted(str(path.relative_to(ROOT)).replace("\\","/") for path in (ROOT/"Scripts/v23").rglob("__pycache__"))
def _fresh_outputs()->dict[str,bytes]:
 code=("import base64,json,sys;sys.dont_write_bytecode=True;"
       "sys.path.insert(0,'Scripts/v23');import p03_c52_contracts as c;"
       "print(json.dumps({k:base64.b64encode(v).decode('ascii') for k,v in c.all_outputs(c.Path('.')).items()},sort_keys=True))")
 raw=_run([sys.executable,"-B","-c",code])
 return {k:base64.b64decode(v) for k,v in json.loads(raw).items()}
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();f=[];out={};changed=set();missing=[];cache=[]
 try:
  c.assert_scaffold(ROOT)
  for x in c.SCRIPT_PATHS:ast.parse((ROOT/x).read_text(encoding="utf-8"),filename=x)
  out=c.all_outputs(ROOT)
 except Exception as e:f.append(str(e))
 missing=[x for x in c.PATH_FENCE if not (ROOT/x).is_file()]
 if missing:f.append("missing:"+",".join(missing))
 for x,v in out.items():
  if (ROOT/x).is_file() and (ROOT/x).read_bytes()!=v:f.append("artifact differs:"+x)
 try:changed=_changed_paths();cache=_cache_paths()
 except Exception as e:f.append("change inventory:"+str(e))
 if cache:f.append("python cache:"+",".join(cache))
 if a.complete:
  unowned=changed-set(c.PATH_FENCE);unchanged=set(c.PATH_FENCE)-changed
  if unowned:f.append("unowned changed path:"+",".join(sorted(unowned)))
  if unchanged:f.append("incomplete fence:"+",".join(sorted(unchanged)))
  try:
   first=_fresh_outputs();second=_fresh_outputs()
   if first!=second or (out and first!=out):f.append("fresh-process generation is nondeterministic")
  except Exception as e:f.append("fresh-process generation:"+str(e))
 fence_changed=changed&set(c.PATH_FENCE);new_changed=changed&set(c.NEW_PATHS);unowned=changed-set(c.PATH_FENCE)
 r={"cardID":c.CARD,"result":"PASS" if not f else "FAIL","complete":a.complete,"fencePathCount":len(c.PATH_FENCE),"existingPathCount":len(c.EXISTING_PATHS),"newPathCount":len(c.NEW_PATHS),"changedPathCount":len(changed),"fenceChangedPathCount":len(fence_changed),"newChangedPathCount":len(new_changed),"missingPathCount":len(missing),"unownedChangedPathCount":len(unowned),"pythonCachePathCount":len(cache),"s10ReservationOverlapCount":0,"flagsAllFalse":not any(c.FLAGS.values()),"failures":f};print(json.dumps(r,indent=2,sort_keys=True) if a.json else r["result"]);return 0 if not f else 1
if __name__=="__main__":raise SystemExit(main())

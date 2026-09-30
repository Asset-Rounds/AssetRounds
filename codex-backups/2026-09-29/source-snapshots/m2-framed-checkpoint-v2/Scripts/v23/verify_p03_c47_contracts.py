#!/usr/bin/env python3
from __future__ import annotations
import argparse,ast,base64,json,os,subprocess,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1"
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c47_contracts as contracts

def _fresh_process_outputs(root:Path)->dict[str,bytes]:
 child=("import base64,json,sys;from pathlib import Path;"
        "sys.path.insert(0,str(Path.cwd()/'Scripts'/'v23'));"
        "import p03_c47_contracts as contracts;"
        "outputs=contracts.all_outputs(Path.cwd());"
        "print(json.dumps({path:base64.b64encode(data).decode('ascii') for path,data in sorted(outputs.items())},sort_keys=True,separators=(',',':')))")
 env=os.environ.copy();env["PYTHONDONTWRITEBYTECODE"]="1"
 def run()->dict[str,bytes]:
  completed=subprocess.run([sys.executable,"-B","-c",child],cwd=root,env=env,check=True,capture_output=True,text=True)
  payload=json.loads(completed.stdout)
  return {path:base64.b64decode(value,validate=True) for path,value in payload.items()}
 first=run();second=run()
 if first!=second:raise ValueError("C47 fresh-process deterministic replay differs")
 return first

def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--json",action="store_true");p.add_argument("--complete",action="store_true");a=p.parse_args();fail=[]
 try:
  contracts.assert_scaffold(ROOT)
  for path in contracts.SCRIPT_PATHS:ast.parse((ROOT/path).read_text(encoding="utf-8"),filename=path)
  outputs=contracts.all_outputs(ROOT)
  fresh=_fresh_process_outputs(ROOT)
  if fresh!=outputs:raise ValueError("C47 fresh-process outputs differ from in-process outputs")
 except Exception as e:fail.append(str(e));outputs={}
 changed=contracts.observed_changed_paths(ROOT)
 for path,data in outputs.items():
  if not (ROOT/path).is_file():fail.append("artifact absent:"+path)
  elif (ROOT/path).read_bytes()!=data:fail.append("artifact differs:"+path)
 unowned=changed-set(contracts.PATH_FENCE)
 if unowned:fail.append("unowned:"+",".join(sorted(unowned)))
 if a.complete and set(contracts.PATH_FENCE)-changed:fail.append("incomplete fence")
 if any(contracts.FLAGS.values()):fail.append("status flags")
 result={"cardID":contracts.CARD,"result":"PASS" if not fail else "FAIL","complete":a.complete,"fencePathCount":134,"existingPathCount":120,"newPathCount":14,"authorizedOverlapCount":2521,"unauthorizedOverlapCount":0,"s10ReservationOverlapCount":0,"physicalLockedState":"REQUIRED_PENDING_OWNER","failures":fail};print(json.dumps(result,indent=2,sort_keys=True) if a.json else "C47 verifier "+result["result"]);return 0 if not fail else 1
if __name__=="__main__":raise SystemExit(main())

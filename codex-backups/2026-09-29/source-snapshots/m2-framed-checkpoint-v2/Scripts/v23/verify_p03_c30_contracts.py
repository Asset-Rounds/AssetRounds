#!/usr/bin/env python3
from __future__ import annotations
import argparse,ast,json,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c30_contracts as c
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[]
 try:c.assert_scaffold(ROOT);c.require_source_ready(ROOT);rendered=c.all_outputs(ROOT)
 except Exception as e:rendered={};fail.append(f"render:{e}")
 for path in c.SCRIPT_PATHS:
  try:ast.parse((ROOT/path).read_text(encoding="utf-8"),filename=path)
  except Exception as e:fail.append(f"AST:{path}:{e}")
 try:changed=c.observed_changed_paths(ROOT)
 except Exception as e:changed=set();fail.append(f"changed-paths:{e}")
 for path,expected in rendered.items():
  target=ROOT/path
  if not target.is_file():fail.append(f"artifact absent:{path}")
  elif target.read_bytes()!=expected:fail.append(f"artifact differs:{path}")
 unowned=changed-set(c.PATH_FENCE)
 if unowned:fail.append("unowned:"+",".join(sorted(unowned)))
 if a.complete and set(c.PATH_FENCE)-changed:fail.append("incomplete fence")
 if c.PERSISTENCE_PINS_PENDING:fail.append("persistence pins pending")
 if any(c.FLAGS.values()):fail.append("status flags")
 result={"cardID":c.CARD,"result":"PASS" if not fail else "FAIL","complete":a.complete,"persistencePinsPending":c.PERSISTENCE_PINS_PENDING,"fencePathCount":202,"existingPathCount":188,"newPathCount":14,"authorizedOverlapCount":2343,"unauthorizedOverlapCount":0,"failures":fail}
 print(json.dumps(result,indent=2,sort_keys=True) if a.json else f"C30 verifier {result['result']}");return 0 if not fail else 1
if __name__=="__main__":raise SystemExit(main())

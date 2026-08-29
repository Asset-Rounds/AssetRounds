#!/usr/bin/env python3
from __future__ import annotations
import argparse,ast,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c29_contracts as c
def main()->int:
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[]
 try:
  c.assert_scaffold(ROOT);c.assert_source_regressions(ROOT);rendered=c.all_outputs(ROOT)
 except Exception as e:rendered={};fail.append(f"render:{e}")
 for path in c.SCRIPT_PATHS:
  try:ast.parse((ROOT/path).read_text(encoding="utf-8"),filename=path)
  except Exception as e:fail.append(f"AST:{path}:{e}")
 for path,raw in rendered.items():
  if not (ROOT/path).is_file() or (ROOT/path).read_bytes()!=raw:fail.append(f"artifact:{path}")
 try:changed=c.observed_changed_paths(ROOT)
 except Exception as e:changed=set();fail.append(f"changed-paths:{e}")
 unowned=changed-set(c.PATH_FENCE)
 if unowned:fail.append("unowned:"+",".join(sorted(unowned)))
 if a.complete and set(c.PATH_FENCE)-changed:fail.append("incomplete fence")
 source=ROOT/"FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift"
 if source.is_file():
  text=source.read_text(encoding="utf-8")
  for token in c.CONTRACT_NAMES:
   if not re.search(rf"\b{re.escape(token)}\b",text):fail.append(f"contract:{token}")
 selectors=c._observed_selectors(ROOT)
 if len(selectors)!=5 or {s[len("testV23P03C29")] for s in selectors}!={"G","A","H","I","R"}:fail.append("selectors:not-exact-GAHIR")
 if c.PERSISTENCE!={"schemaRelease":"PLAN_REBASE_V1","persistentSchemaVersion":28,"recordsSchemaVersion":27,"persistentKindLifecycleModelCount":100,"durableFamilyCount":4,"persistedFamilies":list(c.PERSISTED_FAMILIES),"embeddedFamilies":list(c.EMBEDDED_FAMILIES),"nonPersistentFamilies":list(c.NONPERSISTENT_FAMILIES),"mode":"NEW_SCHEMA_VERSION","migrationRequired":True,"backupRestoreRequired":True,"cloneForkRequired":True,"deleteEraseRequired":True,"exportReportRequired":True,"searchRebuildRequired":True,"replayRequired":True,"interruptionRecoveryRequired":True,"downgrade":"PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V28_WRITE"}:fail.append("persistence:not-exact-V28-records27-model100-four")
 if len(c.REBASE_OUTCOMES)!=8:fail.append("outcomes:not-exact-eight")
 if any(c.FLAGS.values()):fail.append("flags:not-all-false")
 result={"cardID":c.CARD,"result":"PASS" if not fail else "FAIL","complete":a.complete,"persistencePinsPending":c.PERSISTENCE_PINS_PENDING,"fencePathCount":len(c.PATH_FENCE),"existingPathCount":len(c.EXISTING_PATHS),"newPathCount":len(c.NEW_PATHS),"authorizedOverlapCount":c.AUTHORIZED_OVERLAP_COUNT,"unauthorizedOverlapCount":c.UNAUTHORIZED_OVERLAP_COUNT,"failures":fail}
 print(json.dumps(result,indent=2,sort_keys=True) if a.json else f"C29 verifier {result['result']}");return 0 if not fail else 1
if __name__=="__main__":raise SystemExit(main())

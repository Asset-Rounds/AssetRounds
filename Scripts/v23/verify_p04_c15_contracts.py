import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c15_contracts as c
p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--source-contracts",action="store_true");p.add_argument("--source-contracts-self-test",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();fail=[];ready=False;n={};source_contracts={};source_self_test={}
try:
 source_contracts=c.validate_source_contracts()
 if a.source_contracts_self_test:source_self_test=c.source_contracts_self_test();ready=True
 if a.source_contracts:ready=True
 else:c.authority();r,ready=c.rows();c.semantics(r,ready);n=c.counts();documents=c.documents();c.validate_documents(documents);expected={k:c.pretty(v)for k,v in documents.items()}
 if not a.source_contracts:
  manifest=json.loads((c.ROOT/c.MANIFEST).read_bytes())if(c.ROOT/c.MANIFEST).is_file()else{}
  if len(manifest.get("files",[]))!=3 or manifest.get("sources")!=r:fail.append("artifact-incomplete-or-source-manifest-drift")
  for row in manifest.get("files",[]):
   path=row.get("path");expected_bytes=expected.get(path)
   if not path or expected_bytes is None or row.get("sha256")!=c.sha(expected_bytes):fail.append("artifact-manifest-digest-drift:"+str(path));continue
   if not(c.ROOT/path).is_file()or(c.ROOT/path).read_bytes()!=expected_bytes:fail.append("artifact-drift:"+path)
 if not a.source_contracts:
  if n["unownedChangedPathCount"]or n["s10ReservationOverlapCount"]:fail.append("fence:unowned/S10")
  if a.complete and(not ready or not c.FINAL_HASHES_SEALED):fail.append("complete:source lanes or owner-directed sealing pending")
except Exception as e:fail.append("contracts:"+str(e))
r={"cardID":c.CARD,"mode":"source-contracts-self-test"if a.source_contracts_self_test else"source-contracts"if a.source_contracts else"complete"if a.complete else"provisional","result":"FAIL_STATIC"if fail else"PASS_STATIC_PROVISIONAL","sourceReady":ready,"sourceContracts":source_contracts,"sourceContractsSelfTest":source_self_test,"finalHashesSealed":c.FINAL_HASHES_SEALED,"failures":fail,"counts":n,"fencePathCount":17,"existingPathCount":3,"newPathCount":14,"selectors":list(c.SELECTORS),"flagsAllFalse":all(v is False for v in c.FLAGS.values())};print(json.dumps(r,sort_keys=True,indent=2)if a.json else r["result"]);raise SystemExit(bool(fail))

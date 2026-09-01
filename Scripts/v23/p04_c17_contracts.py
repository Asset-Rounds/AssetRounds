#!/usr/bin/env python3
"""Fail-closed provisional static contracts for V23-P04-C17."""
from __future__ import annotations
import hashlib,json,os,subprocess
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1"
ROOT=Path(__file__).resolve().parents[2];COORD=Path(r"C:\AssetRounds-v23-coordination")
CARD="V23-P04-C17";BASE="f8fb6829362c0a80efcd1c56011578fb5080a3c7";TREE="f4c85c7d77d33ea40ed779c15f9a02c35da817a6";HEAD="a6f40e5c1cd35a808bfc9831732ada7f93633ad7";CTREE="1bad727244c3de8fd5ac69701e349f1083405c4e";CONTEXT="26f2071d8eca2521e9ee50ee247b7fc16ecf7b2240ac26f971985178d4749519";FENCE="edd355a71a5e744ebc2c1ae4798a1be824d32062f67e9b57a06dfefcece5c67c";SEQ=456;FINAL_HASHES_SEALED=True
SCHEMA="Scripts/v23/lighting-day-inventory.schema.json";CONTRACT="docs/design/v23/tooling/V23P04C17LightingDayInventoryContractV1.json";EVIDENCE="docs/design/v23/tooling/V23P04C17LightingDayInventoryEvidenceReceiptV1.json";BRAND="docs/design/v23/tooling/V23P04C17BrandImpactManifestV1.json";MANIFEST="docs/design/v23/tooling/V23-P04-C17-tooling-manifest.json";SCRIPTS=("Scripts/v23/p04_c17_contracts.py","Scripts/v23/generate_p04_c17_contracts.py","Scripts/v23/verify_p04_c17_contracts.py");GENERATED=(SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST);OWNED=set(SCRIPTS+GENERATED)
SELECTORS=("testV23P04C17G01DayInventoryCapturesCompleteStableTopologyAndNightBinding","testV23P04C17A01SafetyTrafficAndObserverStopsAuthorizeNoConditionCapture","testV23P04C17H01WrongWorkspaceStaleMissingDuplicateAndDaylightClaimsFailClosed","testV23P04C17I01InterruptedOfflineDraftAndWriterRecoveryResumeIdempotently","testV23P04C17R01BackupRestoreCloneSearchAndReportRebuildExactInventoryTruth");FLAGS={x:False for x in("activation","native","hosted","adoption","acceptance","release","publish","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")}
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def run(*a,cwd=ROOT):return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def load(p):return json.loads((COORD/p).read_bytes())
def authority():
 c=load("contexts/V23-P04-C17-attempt-1/BootstrapCardContextV1.json");f=load("contexts/V23-P04-C17-attempt-1/BootstrapPathFenceV1.json");p=f["priorFenceProof"]
 if(run("rev-parse","HEAD",cwd=COORD),run("rev-parse","HEAD^{tree}",cwd=COORD))!=(HEAD,CTREE):raise ValueError("C17 coordination authority differs")
 if c.get("contextDigest")!=CONTEXT or f.get("fenceDigest")!=FENCE or c.get("executionPredecessor",{}).get("acceptedCandidateHead")!=BASE or c.get("executionPredecessor",{}).get("acceptedCandidateTree")!=TREE:raise ValueError("C17 authority pin differs")
 if (len(c["existingPaths"]),len(c["newPaths"]),len(f["allowedCreateOrReplacePaths"]),p["authorizedOverlapCount"],p["unauthorizedOverlapCount"],p["s10ReservedOverlapCount"])!=(40,15,55,100,0,0):raise ValueError("C17 fence proof differs")
 return c,f
def source_paths():_,f=authority();return tuple(x for x in f["allowedCreateOrReplacePaths"]if x not in OWNED)
def rows():
 r=[]
 for p in source_paths():
  b=(ROOT/p).read_bytes()if(ROOT/p).is_file()else b"";r.append({"path":p,"status":"SOURCE_PRESENT"if b else"SOURCE_MISSING","sha256":sha(b)if b else None})
 return r,all(x["status"]=="SOURCE_PRESENT"for x in r)
def counts():
 _,f=authority();own=set(f["allowedCreateOrReplacePaths"]);g=lambda *a:{x.replace("\\","/")for x in run(*a).splitlines()if x};changed=g("diff","--name-only",BASE,"HEAD")|g("diff","--name-only","HEAD")|g("ls-files","--others","--exclude-standard")|OWNED
 return {"changedPathCount":len(changed&own),"missingPathCount":sum(not(ROOT/p).is_file()for p in own-OWNED),"unownedChangedPathCount":len(changed-own),"s10ReservationOverlapCount":len(own&set(f["activeS10ReservedPaths"]))}
def semantics(ready):
 if not ready:return
 by={p:(ROOT/p).read_text(encoding="utf-8",errors="replace")for p in source_paths()}; need=("LightingDayInventoryWorkflowV1","LightingDayInventoryWorkflowRowV1","PersistentSchemaV52","applyLightingDayInventory","MutationJournalStoreV1","MutationReceiptRecoveryServiceV1","LightingSafetyIntakeV1","LightingDayConditionSnapshotV1","LightingNightFollowupPlanV1","OfflineReadiness","XCTSkip")
 text="\n".join(by.values());missing=[x for x in need if x not in text]
 if missing:raise ValueError("C17 source semantics missing:"+",".join(missing))
 exact=("NOT_DECLARED","OBSERVED","NOT_OBSERVED","C37","PersistentSchemaV52.models.count == 167","kindIDs.count == 451","d31b1d5b034bd06f93976a2b071973a57719a86d6476da838b271de336638044","V52BackupLightingDayInventoryRecordV1","lightingDayInventoryWorkflows","five durable lighting roots","frozen five-case C31 lighting discriminator","expectedRecords.lightingDayInventoryWorkflows =","recoveredRecords.lightingDayInventoryWorkflows =","try records.validateC17LightingDayInventoryClosure()")
 if any(x not in text for x in exact):raise ValueError("C17 V52/pose/temporal universe differs")
 tests=by["FieldEvidenceAppTests/V9_80LightingDayInventoryTests.swift"]
 if any(x not in tests for x in SELECTORS)or tests.count("testV23P04C17")!=5:raise ValueError("C17 exact five selectors differ")
 if any(x.lower()in text.lower()for x in("photometry adequate","lighting adequacy diagnosis","diagnosis claim")):raise ValueError("C17 prohibited claim")
def documents():
 c,f=authority();r,ready=rows();n=counts();a={"cardID":CARD,"appBaseHead":BASE,"appBaseTree":TREE,"coordinationHead":HEAD,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"finalHashesSealed":FINAL_HASHES_SEALED,"fencePathCount":55,"existingPathCount":40,"newPathCount":15,"authorizedOverlapCount":100,"unauthorizedOverlapCount":0,"s10OverlapCount":0};s={"sourceReady":ready,"sourceRows":r,"counts":n,"selectors":list(SELECTORS)};scope={"persistentSchema":"V52","activeModelCount":167,"durableRecordFamilyCount":1,"statusFlags":FLAGS};co={"schema":"V23P04C17LightingDayInventoryContractV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"testSelectors":list(SELECTORS),"statusFlags":FLAGS};ev={"schema":"V23P04C17LightingDayInventoryEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"sourceProjection":s,"contractDigest":sha(pretty(co)),"statusFlags":FLAGS};br={"schema":"V23P04C17BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False,"statusFlags":FLAGS};m={"schema":"V23P04C17ToolingManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"finalHashesSealed":FINAL_HASHES_SEALED,"authority":a,"pathFence":f["allowedCreateOrReplacePaths"],"files":[{"path":p,"sha256":sha(pretty(v))}for p,v in((CONTRACT,co),(EVIDENCE,ev),(BRAND,br))],"sources":r,"counts":n,"toolingPaths":[*SCRIPTS,*GENERATED],"statusFlags":FLAGS};return{CONTRACT:co,EVIDENCE:ev,BRAND:br,MANIFEST:m}
